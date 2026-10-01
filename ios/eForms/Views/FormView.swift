import SwiftUI

@MainActor
struct FormView: View {
    private struct PopulationOption: Identifiable {
        let id: String
        let label: String
        let snapshot: JSONObject?
    }

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var store = AppStore.shared
    let route: FormRoute
    let form: JSONObject
    let fields: JSONArray
    let readOnly: Bool
    let draftID: String
    let formID: String
    let createdAt: Int64
    @State private var checkpoint: JSONObject?

    @State private var values: JSONObject
    @State private var population: JSONObject?
    @State private var populationSelection: String
    @State private var dirty = false
    @State private var autosave = true
    @State private var message: String?
    @State private var savedStatus: String
    @State private var showDiscard = false
    @State private var showPortalFallback = false
    @State private var clearTokens: [String: Int] = [:]

    init(route: FormRoute) {
        self.route = route
        let store = AppStore.shared
        var source: JSONObject?
        var isReadOnly = false
        if let id = route.outboxID { source = store.outboxSubmission(id: id); isReadOnly = true }
        else if let uuid = route.sentUUID { source = store.sentSubmission(uuid: uuid); isReadOnly = true }
        else if let id = route.draftID { source = store.draft(id: id) }

        let resolvedForm = source?.object("form") ?? store.form(id: route.formID) ?? [:]
        let resolvedFormID = source?.string("formId") ?? route.formID
        let resolvedDraftID = route.draftID ?? (isReadOnly ? "" : store.newDraftID())
        let initialPopulation = source?.object("populationSnapshot") ?? Self.requestedPopulation(
            in: resolvedForm, populationID: route.populationID, setID: route.populationSetID)

        form = resolvedForm
        fields = resolvedForm.objects("fields")
        readOnly = isReadOnly
        formID = resolvedFormID
        draftID = resolvedDraftID
        createdAt = source?.milliseconds("createdAt", default: nowMilliseconds()) ?? nowMilliseconds()
        _checkpoint = State(initialValue: route.draftID.flatMap { store.draft(id: $0) })
        _values = State(initialValue: source?.object("values") ?? [:])
        _population = State(initialValue: initialPopulation)
        _populationSelection = State(initialValue: Self.populationKey(initialPopulation))
        _savedStatus = State(initialValue: isReadOnly
                             ? (route.outboxID == nil ? "Submitted form — encrypted offline copy" : "Outbox form — encrypted offline copy")
                             : "Encrypted offline copy")
    }

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 11) {
                        populationControl
                        ForEach(Array(fields.enumerated()), id: \.offset) { _, field in
                            if visibleFieldIDs.contains(field.string("id")) {
                                fieldView(field).id(field.string("id"))
                            }
                        }
                        if readOnly {
                            Button("Close") { dismiss() }.buttonStyle(CompactButtonStyle(primary: true)).frame(maxWidth: .infinity)
                        } else {
                            Menu("Done  ▾") {
                                Button("Discard changes", role: .destructive) { showDiscard = true }
                                Button("Save draft") { Task { await saveDraftNow() } }
                                Button("Submit") { submit() }
                            }
                            .buttonStyle(CompactButtonStyle(primary: true)).frame(maxWidth: .infinity)
                        }
                    }
                    .padding(12)
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                Text(savedStatus).font(.caption).foregroundStyle(Color(red: 20/255, green: 108/255, blue: 67/255))
                    .frame(maxWidth: .infinity).padding(.vertical, 5)
                    .background(Color(red: 235/255, green: 246/255, blue: 240/255))
            }
            .navigationTitle(form.string("name", default: "Form"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { close() } }
                if !readOnly {
                    ToolbarItem(placement: .confirmationAction) {
                        Menu("Done") {
                            Button("Discard changes", role: .destructive) { showDiscard = true }
                            Button("Save draft") { Task { await saveDraftNow() } }
                            Button("Submit") { submit() }
                        }
                    }
                }
            }
        }
        .onAppear {
            if !readOnly {
                let changed = applyDefaults(populationChanged: route.populationID != nil)
                if changed || route.populationID != nil { saveLocal() }
            }
        }
        .onDisappear { if !readOnly && autosave && dirty { saveLocal(); BackgroundRefresh.schedule() } }
        .alert("eForms", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("OK") { message = nil }
        } message: { Text(message ?? "") }
        .confirmationDialog("Discard changes?", isPresented: $showDiscard, titleVisibility: .visible) {
            Button("Discard changes", role: .destructive) { discard() }
            Button("Cancel", role: .cancel) {}
        } message: { Text("All changes made since this form was opened or last saved will be lost.") }
        .sheet(isPresented: $showPortalFallback) { PortalView(mode: .home) }
    }

    @ViewBuilder private var populationControl: some View {
        let options = populationOptions
        if !options.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Text("Population" + (form.bool("requirePopulation") ? "  *" : "")).font(.subheadline.weight(.semibold))
                if readOnly {
                    Text(population.map { "\($0.string("setName")) — \($0.string("name"))" } ?? "Blank form")
                        .font(.subheadline).padding(9).frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(white: 0.97)).overlay(Rectangle().stroke(AppTheme.line))
                } else {
                    Picker("Population", selection: $populationSelection) {
                        ForEach(options) { Text($0.label).tag($0.id) }
                    }
                    .pickerStyle(.menu).frame(maxWidth: .infinity, alignment: .leading)
                    .onChange(of: populationSelection) { _, selected in
                        population = options.first(where: { $0.id == selected })?.snapshot
                        _ = applyDefaults(populationChanged: true)
                        dirty = true
                        saveLocal()
                    }
                }
            }
        }
    }

    @ViewBuilder private func fieldView(_ field: JSONObject) -> some View {
        let type = field.string("type")
        let key = field.string("name", default: field.string("id"))
        let disabled = readOnly || isDisabled(field)
        if type == "section" {
            Text(populate(field.string("title", default: "Section"))).font(.headline).foregroundStyle(AppTheme.deep).padding(.top, 5)
        } else if type == "freetext" {
            Text(populate(lines(field["content"]))).font(field.bool("large") ? .title3 : .body)
        } else if type == "image" {
            VStack(alignment: .leading) {
                Text(populate(field.string("heading", default: "Reference image"))).font(.subheadline.weight(.semibold))
                Text("Image available in the online portal").font(.caption).foregroundStyle(AppTheme.muted)
            }
        } else if type == "weblink", let url = URL(string: populate(field.string("url"))) {
            Link(populate(field.string("title", default: url.absoluteString)), destination: url).font(.subheadline)
        } else {
            VStack(alignment: .leading, spacing: 4) {
                let label = populate(field.string("title", default: field.string("heading", default: "Field")))
                if !label.isEmpty { Text(label + (isRequired(field) ? "  *" : "")).font(.subheadline.weight(.semibold)) }
                let hint = populate(lines(field["hint"]))
                if !hint.isEmpty { Text(hint).font(.caption).foregroundStyle(AppTheme.muted) }
                control(field, key: key, type: type, disabled: disabled)
            }
        }
    }

    @ViewBuilder private func control(_ field: JSONObject, key: String, type: String, disabled: Bool) -> some View {
        switch type {
        case "textarea":
            if readOnly {
                ScrollView(.vertical, showsIndicators: false) {
                    Text(values.string(key)).frame(maxWidth: .infinity, alignment: .topLeading).textSelection(.enabled)
                }
                .frame(minHeight: 95, maxHeight: 150).padding(8).overlay(Rectangle().stroke(AppTheme.line))
            } else {
                TextEditor(text: stringBinding(key)).frame(minHeight: 110).scrollContentBackground(.hidden)
                    .padding(3).overlay(Rectangle().stroke(AppTheme.line)).disabled(disabled)
            }
        case "number":
            TextField("Enter a number", text: stringBinding(key)).keyboardType(.decimalPad)
                .textFieldStyle(.roundedBorder).disabled(disabled)
        case "date":
            DatePicker("", selection: dateBinding(key), displayedComponents: .date)
                .labelsHidden().disabled(disabled)
        case "time":
            DatePicker("", selection: timeBinding(key), displayedComponents: .hourAndMinute)
                .labelsHidden().disabled(disabled)
        case "combo":
            Picker("Choose an option", selection: stringBinding(key)) {
                Text("Choose an option…").tag("")
                ForEach(populatedChoices(field), id: \.key) { choice in Text(choice.label).tag(choice.key) }
            }.pickerStyle(.menu).disabled(disabled)
        case "radios":
            VStack(alignment: .leading) {
                ForEach(populatedChoices(field), id: \.key) { choice in
                    Button { setValue(key, choice.key) } label: {
                        HStack { Image(systemName: values.string(key) == choice.key ? "largecircle.fill.circle" : "circle"); Text(choice.label) }
                    }.buttonStyle(.plain).disabled(disabled)
                }
            }
        case "checks":
            VStack(alignment: .leading) {
                ForEach(populatedChoices(field), id: \.key) { choice in
                    Toggle(choice.label, isOn: checkBinding(key, choice.key)).disabled(disabled)
                }
            }
        case "signature":
            SignaturePad(value: stringBinding(key), clearToken: clearTokens[key, default: 0], readOnly: disabled)
                .frame(height: 120)
            if !readOnly {
                Button("Clear signature") { clearTokens[key, default: 0] += 1; setValue(key, nil) }
                    .buttonStyle(CompactButtonStyle(primary: false)).frame(maxWidth: .infinity)
            }
        case "calculated":
            Text(values.string(key, default: "Calculated by eForms")).foregroundStyle(AppTheme.muted)
                .padding(9).frame(maxWidth: .infinity, alignment: .leading).background(Color(white: 0.97))
        case "fileUpload", "imageUpload", "soundRecorder":
            if readOnly {
                Text("Attachment included with submission")
                    .font(.caption).foregroundStyle(AppTheme.muted).padding(9).overlay(Rectangle().stroke(AppTheme.line))
            } else {
                Button("Complete this attachment in the online portal") { showPortalFallback = true }
                    .buttonStyle(CompactButtonStyle(primary: false)).frame(maxWidth: .infinity)
            }
        default:
            if readOnly {
                Text(values.string(key)).frame(maxWidth: .infinity, alignment: .leading).padding(9)
                    .background(Color(white: 0.97)).overlay(Rectangle().stroke(AppTheme.line)).textSelection(.enabled)
            } else {
                TextField("Enter an answer", text: stringBinding(key)).textFieldStyle(.roundedBorder)
                    .textInputAutocapitalization(field.bool("masked") ? .never : .sentences)
                    .disabled(disabled).privacySensitive(field.bool("masked"))
            }
        }
    }

    private var populationOptions: [PopulationOption] {
        guard !form.objects("populationSets").isEmpty else { return [] }
        var output = [PopulationOption(id: "", label: form.bool("requirePopulation") ? "Choose a population…" : "Blank form", snapshot: nil)]
        for set in form.objects("populationSets") {
            for item in set.objects("populations") {
                var snapshot = item
                snapshot["setId"] = set["id"] ?? ""
                snapshot["setName"] = set.string("name")
                let id = Self.populationKey(snapshot)
                output.append(PopulationOption(id: id, label: "\(set.string("name")) · \(item.string("name"))", snapshot: snapshot))
            }
        }
        return output
    }

    private var visibleFieldIDs: Set<String> {
        var result = Set<String>()
        var sectionVisible = true
        for field in fields {
            if field.string("type") == "section" { sectionVisible = evaluateVisibility(field) }
            if sectionVisible && evaluateVisibility(field) { result.insert(field.string("id")) }
        }
        return result
    }

    private func evaluateVisibility(_ field: JSONObject) -> Bool {
        guard let condition = field.object("condition") else { return !(field["visible"] is Bool) || field.bool("visible", default: true) }
        return evaluate(condition)
    }

    private func isRequired(_ field: JSONObject) -> Bool {
        if let condition = field.object("requiredCondition") { return evaluate(condition) }
        return field.bool("required") || field.string("type") == "signature"
    }

    private func isDisabled(_ field: JSONObject) -> Bool {
        if let condition = field.object("readOnlyCondition") { return evaluate(condition) }
        return field.bool("readOnly")
    }

    private func evaluate(_ condition: JSONObject) -> Bool {
        if condition.string("type") == "join" {
            let children = condition.objects("conditions")
            guard !children.isEmpty else { return false }
            return condition.string("join") == "and" ? children.allSatisfy(evaluate) : children.contains(where: evaluate)
        }
        guard let field = fields.first(where: { $0.string("id") == condition.string("fieldId") }) else { return false }
        let value = values[field.string("name")]
        switch condition.string("operation", default: "equals") {
        case "any": return value != nil && !(value is NSNull) && String(describing: value!).isEmpty == false
        case "none": return value == nil || value is NSNull || String(describing: value!).isEmpty
        default:
            if let array = value as? [String] { return array.contains(condition.string("value")) }
            return String(describing: value ?? "") == condition.string("value")
        }
    }

    private func applyDefaults(populationChanged: Bool) -> Bool {
        var changedAny = false
        for _ in 0..<10 {
            var changed = false
            for field in fields where visibleFieldIDs.contains(field.string("id")) && field["defaultValue"] != nil {
                let key = field.string("name")
                guard !key.isEmpty else { continue }
                let raw = field.string("defaultValue")
                let tokenDefault = raw.contains("{{") && raw.contains("}}")
                if tokenDefault && population == nil && form.bool("requirePopulation") { continue }
                let current = values[key]
                let missing = current == nil || current is NSNull
                let blank = (current as? String)?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true
                guard missing || (tokenDefault && (populationChanged || blank || isDisabled(field))) else { continue }
                let resolved = populate(raw)
                if String(describing: current ?? "") != resolved { values[key] = resolved; changed = true; changedAny = true }
            }
            if !changed { break }
        }
        return changedAny
    }

    private func populate(_ input: String) -> String {
        guard let tokens = population?.object("tokenMap") else {
            return input.replacingOccurrences(of: #"\{\{[^}]*\}\}"#, with: "", options: .regularExpression)
        }
        var output = input
        for (key, value) in tokens {
            output = output.replacingOccurrences(of: "{{\(key)}}", with: String(describing: value), options: .caseInsensitive)
        }
        return output
    }

    private struct Choice { let key: String; let label: String }
    private func populatedChoices(_ field: JSONObject) -> [Choice] {
        var output: [Choice] = []
        for choice in field.objects("choices") {
            let raw = choice.string("key")
            if raw.contains("{{") {
                guard population?.object("tokenMap") != nil else { continue }
                output += populate(raw).split(separator: ";").map { Choice(key: $0.trimmingCharacters(in: .whitespaces), label: $0.trimmingCharacters(in: .whitespaces)) }
            } else {
                output.append(Choice(key: raw, label: choice.string("label", default: raw)))
            }
        }
        return output
    }

    private func stringBinding(_ key: String) -> Binding<String> {
        Binding(get: { values.string(key) }, set: { setValue(key, $0.isEmpty ? nil : $0) })
    }

    private func checkBinding(_ key: String, _ choice: String) -> Binding<Bool> {
        Binding(get: { (values[key] as? [String] ?? []).contains(choice) }, set: { checked in
            var selected = values[key] as? [String] ?? []
            selected.removeAll { $0 == choice }
            if checked { selected.append(choice) }
            setValue(key, selected.isEmpty ? nil : selected)
        })
    }

    private func dateBinding(_ key: String) -> Binding<Date> {
        let format = DateFormatter(); format.locale = Locale(identifier: "en_GB"); format.dateFormat = "dd/MM/yyyy"
        return Binding(get: { format.date(from: values.string(key)) ?? Date() }, set: { setValue(key, format.string(from: $0)) })
    }

    private func timeBinding(_ key: String) -> Binding<Date> {
        let format = DateFormatter(); format.locale = Locale(identifier: "en_GB"); format.dateFormat = "HH:mm"
        return Binding(get: { format.date(from: values.string(key)) ?? Date() }, set: { setValue(key, format.string(from: $0)) })
    }

    private func setValue(_ key: String, _ value: Any?) {
        if let value { values[key] = value } else { values.removeValue(forKey: key) }
        dirty = true
        saveLocal()
    }

    private func saveLocal() {
        guard !readOnly else { return }
        do {
            try store.saveDraft(id: draftID, formID: formID, values: values, createdAt: createdAt, population: population)
            savedStatus = "✓ Saved securely on this device"
        } catch { message = "Could not save this answer." }
    }

    private func saveDraftNow() async {
        dirty = true
        saveLocal()
        checkpoint = store.draft(id: draftID)
        savedStatus = "Saved on this device — syncing to eForms Drafts…"
        BackgroundRefresh.schedule()
        let result = await SyncEngine.shared.saveDraft(id: draftID)
        savedStatus = result.ok ? "Saved on this device and in eForms Drafts" : "Saved on this device — waiting to sync"
        message = result.message
    }

    private func submit() {
        if form.bool("requirePopulation") && population == nil { message = "Choose a population before submitting."; return }
        for field in fields where visibleFieldIDs.contains(field.string("id")) && !isDisabled(field) && isRequired(field) {
            let type = field.string("type")
            if ["section", "freetext", "image", "weblink"].contains(type) { continue }
            let key = field.string("name", default: field.string("id"))
            let value = values[key]
            let missing = value == nil || value is NSNull ||
                (value as? String)?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true ||
                (((value as? [Any])?.count ?? 1) < field.integer("requireCount", default: 1))
            if missing {
                message = ["fileUpload", "imageUpload", "soundRecorder"].contains(type)
                    ? "This form needs an attachment; complete it in the online portal."
                    : "Complete: \(field.string("title", default: "required field"))"
                return
            }
            if type == "number", let number = Double(String(describing: value!)) {
                if let min = field["min"] as? NSNumber, number < min.doubleValue { message = "Check the number entered for \(field.string("title"))"; return }
                if let max = field["max"] as? NSNumber, number > max.doubleValue { message = "Check the number entered for \(field.string("title"))"; return }
            }
        }
        do {
            saveLocal()
            try store.queueDraft(id: draftID)
            dirty = false
            autosave = false
            BackgroundRefresh.schedule()
            Task { _ = await SyncEngine.shared.run(); AppModel.shared.updateAttendance() }
            dismiss()
        } catch { message = error.localizedDescription }
    }

    private func discard() {
        do {
            autosave = false
            try store.discardDraft(id: draftID, checkpoint: checkpoint)
            dismiss()
        } catch { message = error.localizedDescription }
    }

    private func close() { if !readOnly && dirty { saveLocal(); BackgroundRefresh.schedule() }; dismiss() }

    private func lines(_ value: Any?) -> String {
        if let strings = value as? [String] { return strings.joined(separator: "\n") }
        if let values = value as? [Any] { return values.map { String(describing: $0) }.joined(separator: "\n") }
        return value.map { String(describing: $0) } ?? ""
    }

    private static func populationKey(_ snapshot: JSONObject?) -> String {
        guard let snapshot else { return "" }
        return "\(snapshot.string("setId")):\(snapshot.string("id"))"
    }

    private static func requestedPopulation(in form: JSONObject, populationID: String?, setID: String?) -> JSONObject? {
        guard let populationID else { return nil }
        for set in form.objects("populationSets") where setID == nil || set.string("id") == setID {
            if var item = set.objects("populations").first(where: { $0.string("id") == populationID }) {
                item["setId"] = set["id"] ?? ""
                item["setName"] = set.string("name")
                return item
            }
        }
        return nil
    }
}

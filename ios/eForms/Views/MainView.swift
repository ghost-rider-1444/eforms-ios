import SwiftUI

struct FormRoute: Identifiable {
    let id = UUID()
    var formID = ""
    var draftID: String?
    var sentUUID: String?
    var outboxID: String?
    var populationID: String?
    var populationSetID: String?
}

struct MainView: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject private var store = AppStore.shared
    @ObservedObject private var network = NetworkMonitor.shared
    @State private var route: FormRoute?
    @State private var showDashboard = false
    @State private var showPrivacy = false
    @State private var showDeleteDrafts = false
    @State private var showLogout = false
    @State private var accountName = ""

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                header
                statusStrip
                if model.attendance.available { attendanceButton }
                searchAndTabs
                content
            }
            .background(Color.white)
            .toolbar(.hidden, for: .navigationBar)
        }
        .fullScreenCover(isPresented: $model.showLogin) {
            PortalView(mode: .login, required: !store.hasAccountBinding) { Task { await model.loginFinished() } }
                .interactiveDismissDisabled(!store.hasAccountBinding)
        }
        .sheet(isPresented: $showDashboard) { PortalView(mode: .dashboard) }
        .sheet(isPresented: $showPrivacy) { NavigationStack { PrivacyView() } }
        .sheet(isPresented: $model.showAttendance) {
            AttendanceSessionsView(snapshot: model.attendance) { entry in
                model.showAttendance = false
                route = route(for: entry)
            }
        }
        .sheet(isPresented: $model.showAccountConfirmation) { accountConfirmation }
        .fullScreenCover(item: $route) { FormView(route: $0) }
        .alert("eForms", isPresented: Binding(
            get: { model.message != nil },
            set: { if !$0 { model.message = nil } }
        )) { Button("OK") { model.message = nil } } message: { Text(model.message ?? "") }
        .confirmationDialog("Delete all \(store.drafts.count) drafts?", isPresented: $showDeleteDrafts,
                            titleVisibility: .visible) {
            Button("Delete \(store.drafts.count) drafts", role: .destructive) { deleteDrafts() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Only drafts will be deleted. Forms, Outbox and Sent items will not be changed.")
        }
        .confirmationDialog("Log out and erase this device?", isPresented: $showLogout,
                            titleVisibility: .visible) {
            Button("Log out and erase", role: .destructive) { Task { await model.logout() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("All downloaded forms, drafts, Outbox items, sent copies, pins and login data will be removed from this device. Nothing online will be deleted.")
        }
        .confirmationDialog("Different account detected", isPresented: $model.showAccountMismatch,
                            titleVisibility: .visible) {
            Button("Erase local data", role: .destructive) { Task { await model.eraseForDifferentAccount() } }
            Button("Try again", role: .cancel) { model.showAccountConfirmation = true }
        } message: {
            Text("The encrypted offline forms belong to a different University username. Erasing removes only this app’s local data; nothing in Manchester eForms online will be changed.")
        }
        .onChange(of: store.revision) { _, _ in model.updateAttendance() }
    }

    private var header: some View {
        HStack(spacing: 7) {
            Text("eForms").font(.title2).foregroundStyle(.white)
            Spacer()
            Button("Dashboard") {
                if network.isOnline && !model.session.isReviewDemo { showDashboard = true }
                else { model.message = "The online dashboard needs an internet connection." }
            }
            Button(model.syncing ? "Updating…" : "Refresh") { Task { await model.refresh() } }
                .disabled(model.syncing || !network.isOnline || model.session.isReviewDemo)
            Button("Log out") { showLogout = true }
        }
        .font(.caption)
        .buttonStyle(.bordered)
        .tint(.white)
        .padding(.horizontal, 13)
        .padding(.vertical, 9)
        .background(AppTheme.deep)
    }

    private var statusStrip: some View {
        let state: (String, Color, Color) = {
            if model.syncing { return ("Updating your forms…", Color(red: 66/255, green: 52/255, blue: 10/255), Color(red: 1, green: 242/255, blue: 188/255)) }
            if model.session.isReviewDemo { return ("App Review demo — sample data stays on this device", AppTheme.deep, Color(red: 239/255, green: 228/255, blue: 246/255)) }
            if !network.isOnline { return ("Offline — showing downloaded folders", Color(red: 84/255, green: 69/255, blue: 12/255), Color(red: 1, green: 242/255, blue: 188/255)) }
            return ("Up to date and available offline", Color(red: 17/255, green: 91/255, blue: 58/255), Color(red: 219/255, green: 245/255, blue: 232/255))
        }()
        return Text(state.0).font(.caption).foregroundStyle(state.1)
            .frame(maxWidth: .infinity).padding(.vertical, 5).background(state.2)
    }

    private var attendanceButton: some View {
        let label: String = {
            switch model.attendance.level {
            case .red: return "Attendance overdue"
            case .amber: return "Attendance due soon"
            case .green: return model.attendance.incompleteCount == 0 ? "Attendance complete  ✓" : "Attendance up to date  ✓"
            }
        }()
        return Button { model.showAttendance = true } label: {
            Text(label).font(.caption).frame(maxWidth: .infinity).padding(.vertical, 8)
        }
        .foregroundStyle(AppTheme.foreground(for: model.attendance.level))
        .background(AppTheme.background(for: model.attendance.level))
        .overlay(Rectangle().stroke(AppTheme.foreground(for: model.attendance.level).opacity(0.55)))
        .padding(.horizontal, 12).padding(.top, 5)
    }

    private var searchAndTabs: some View {
        VStack(spacing: 7) {
            TextField("Search \(model.activeFolder.rawValue.lowercased())", text: $model.search)
                .textFieldStyle(.roundedBorder).font(.subheadline)
            Picker("Folder", selection: $model.activeFolder) {
                ForEach(AppModel.Folder.allCases) { folder in
                    Text(folder.rawValue + countSuffix(folder)).tag(folder)
                }
            }
            .pickerStyle(.segmented)
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
    }

    private var content: some View {
        ScrollView {
            LazyVStack(spacing: 5) {
                switch model.activeFolder {
                case .forms: formsContent
                case .drafts: submissions(store.drafts, empty: "No drafts", kind: .drafts)
                case .outbox: submissions(store.outbox, empty: "Outbox is empty", kind: .outbox)
                case .sent: submissions(store.sent, empty: "No submitted forms", kind: .sent)
                }
            }
            .padding(.horizontal, 12).padding(.bottom, 22)
        }
    }

    @ViewBuilder private var formsContent: some View {
        let visible = filtered(store.formsPinnedFirst())
        if visible.isEmpty {
            emptyCard(model.search.isEmpty ? "No forms downloaded" : "No matching forms")
        } else {
            let pinned = visible.filter { store.isFormPinned($0.string("id")) }
            if !pinned.isEmpty { category("Pinned", key: "__pinned__", items: pinned, forceOpen: !model.search.isEmpty) }
            let ordinary = visible.filter { !store.isFormPinned($0.string("id")) }
            let names = Array(Set(ordinary.map { $0.string("workspaceName", default: "Forms") })).sorted()
            ForEach(names, id: \.self) { name in
                category(name, key: name, items: ordinary.filter { $0.string("workspaceName", default: "Forms") == name }, forceOpen: !model.search.isEmpty)
            }
        }
        Button("Privacy & data use") { showPrivacy = true }
            .font(.caption).foregroundStyle(AppTheme.muted).padding(.top, 18).padding(.bottom, 5)
    }

    @ViewBuilder private func category(_ title: String, key: String, items: JSONArray, forceOpen: Bool) -> some View {
        let collapsed = !forceOpen && store.isCategoryCollapsed(key)
        Button {
            try? store.toggleCategory(key)
        } label: {
            HStack { Text(collapsed ? "▸" : "▾"); Text(title); Spacer(); Text("\(items.count)") }
                .font(.subheadline).foregroundStyle(AppTheme.deep).padding(.vertical, 7)
        }
        if !collapsed {
            ForEach(Array(items.enumerated()), id: \.offset) { _, form in formRow(form) }
        }
    }

    private func formRow(_ form: JSONObject) -> some View {
        HStack(spacing: 7) {
            Button(store.isFormPinned(form.string("id")) ? "★" : "☆") { try? store.toggleFormPinned(form.string("id")) }
                .font(.body).foregroundStyle(AppTheme.purple).buttonStyle(.plain)
                .accessibilityLabel(store.isFormPinned(form.string("id")) ? "Unpin form" : "Pin form")
            Button {
                route = FormRoute(formID: form.string("id"))
            } label: {
                HStack { Text(form.string("name", default: "Form")).font(.subheadline); Spacer(); Text("›").font(.title3) }
                    .foregroundStyle(AppTheme.ink).padding(.vertical, 8)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 8)
        .background(Color.white)
        .overlay(Rectangle().stroke(AppTheme.line))
    }

    private enum SubmissionKind: Equatable { case drafts, outbox, sent }

    @ViewBuilder private func submissions(_ source: JSONArray, empty: String, kind: SubmissionKind) -> some View {
        let items = filtered(source)
        if kind == .drafts, !source.isEmpty {
            Button("Delete all drafts") { showDeleteDrafts = true }
                .buttonStyle(CompactButtonStyle(primary: false)).frame(maxWidth: .infinity, alignment: .trailing)
        }
        if items.isEmpty { emptyCard(model.search.isEmpty ? empty : "No matching forms") }
        ForEach(Array(items.enumerated()), id: \.offset) { _, item in
            Button { open(item, kind: kind) } label: {
                HStack {
                    Text(title(item)).font(.subheadline).multilineTextAlignment(.leading)
                    Spacer(); Text("›").font(.title3)
                }
                .foregroundStyle(AppTheme.ink).padding(9)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.white).overlay(Rectangle().stroke(AppTheme.line))
            }
            .buttonStyle(.plain)
        }
    }

    private func open(_ item: JSONObject, kind: SubmissionKind) {
        switch kind {
        case .drafts:
            route = FormRoute(formID: item.string("formId"), draftID: item.string("localId"))
        case .outbox:
            let id = item.string("localId").isEmpty ? item.string("uuid") : item.string("localId")
            if store.outboxSubmission(id: id) != nil { route = FormRoute(outboxID: id) }
            else { Task { let result = await SyncEngine.shared.downloadOutbox(uuid: id); if result.ok { route = FormRoute(outboxID: id) } else { model.message = result.message } } }
        case .sent:
            let uuid = item.string("uuid")
            if store.sentSubmission(uuid: uuid) != nil { route = FormRoute(sentUUID: uuid) }
            else { Task { let result = await SyncEngine.shared.downloadSent(uuid: uuid); if result.ok { route = FormRoute(sentUUID: uuid) } else { model.message = result.message } } }
        }
    }

    private func route(for entry: AttendanceEntry) -> FormRoute {
        if !entry.sentUUID.isEmpty { return FormRoute(sentUUID: entry.sentUUID) }
        if !entry.outboxID.isEmpty { return FormRoute(outboxID: entry.outboxID) }
        return FormRoute(formID: entry.formID,
                         draftID: entry.draftID.isEmpty ? nil : entry.draftID,
                         populationID: entry.draftID.isEmpty ? entry.populationID : nil,
                         populationSetID: entry.draftID.isEmpty ? entry.populationSetID : nil)
    }

    private var accountConfirmation: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Enter the University username used to sign in. Only a one-way hash is stored, preventing one student’s offline forms from being synced into another account.")
                    TextField("University username", text: $accountName).textInputAutocapitalization(.never).autocorrectionDisabled()
                }
            }
            .navigationTitle("Confirm this account")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Continue") { Task { if await model.confirmAccount(username: accountName) { accountName = "" } } }
                }
            }
        }
        .interactiveDismissDisabled()
        .presentationDetents([.medium])
    }

    private func deleteDrafts() {
        do {
            let count = try store.deleteAllDrafts()
            model.message = "\(count) draft(s) removed from this device. Online deletions will sync when connected."
            BackgroundRefresh.schedule()
            Task { await model.refresh(manual: false) }
        } catch { model.message = error.localizedDescription }
    }

    private func filtered(_ source: JSONArray) -> JSONArray {
        let query = model.search.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return source }
        return source.filter { item in
            [item.string("name"), item.string("title"), item.string("formName"), item.string("workspaceName")]
                .joined(separator: " ").lowercased().contains(query)
        }
    }

    private func title(_ item: JSONObject) -> String {
        let options = [item.string("title"), item.string("formName"), item.object("formSnapshot")?.string("name") ?? ""]
        return options.first(where: { !$0.isEmpty }) ?? "Form"
    }

    private func countSuffix(_ folder: AppModel.Folder) -> String {
        let count: Int
        switch folder { case .forms: count = store.forms.count; case .drafts: count = store.drafts.count; case .outbox: count = store.outbox.count; case .sent: count = store.sent.count }
        return count > 0 ? " \(count)" : ""
    }

    private func emptyCard(_ text: String) -> some View {
        Text(text).font(.subheadline).foregroundStyle(AppTheme.muted)
            .frame(maxWidth: .infinity).padding(18).overlay(Rectangle().stroke(AppTheme.line))
    }
}

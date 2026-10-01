import Foundation

@MainActor
final class AppStore: ObservableObject {
    static let shared = AppStore()
    private static let schemaVersion = 3

    @Published private(set) var revision = 0
    @Published private(set) var storageFailure: String?
    private let vault: SecureVault
    private var state: JSONObject

    init(vault: SecureVault = .shared) {
        self.vault = vault
        do {
            let loaded = try vault.load()
            if let loaded, loaded.integer("schemaVersion") >= 2 {
                var migrated = loaded
                migrated["schemaVersion"] = Self.schemaVersion
                if migrated["accountHash"] == nil { migrated["accountHash"] = "" }
                state = migrated
                try vault.save(migrated)
            } else {
                state = Self.freshState()
                try vault.save(state)
            }
        } catch {
            state = Self.freshState()
            storageFailure = "The encrypted offline vault could not be opened. Log out to erase the unreadable local copy before saving new work."
        }
    }

    var forms: JSONArray { JSONCopy.array(state.objects("forms")) }
    var drafts: JSONArray { draftMap.values.map(JSONCopy.object) }
    var localOutbox: JSONArray { JSONCopy.array(state.objects("outbox")) }
    var outbox: JSONArray { localOutbox + JSONCopy.array(state.objects("serverOutbox")) }
    var sent: JSONArray { JSONCopy.array(state.objects("sent")) }
    var lastSync: Int64 { state.milliseconds("lastSync") }
    var hasAccountBinding: Bool { !state.string("accountHash").isEmpty }

    func isBound(to hash: String) -> Bool { !hash.isEmpty && state.string("accountHash") == hash }

    @discardableResult
    func bindAccount(_ hash: String) throws -> Bool {
        guard !hash.isEmpty else { return false }
        let current = state.string("accountHash")
        guard current.isEmpty || current == hash else { return false }
        state["accountHash"] = hash
        try persist()
        return true
    }

    func replaceAccount(with hash: String) throws {
        guard !hash.isEmpty else { throw StoreError.invalidAccount }
        state = Self.freshState()
        state["accountHash"] = hash
        try persist()
    }

    func form(id: String) -> JSONObject? {
        forms.first { $0.string("id") == id }.map(JSONCopy.object)
    }

    func formsPinnedFirst() -> JSONArray {
        forms.sorted {
            let left = isFormPinned($0.string("id"))
            let right = isFormPinned($1.string("id"))
            return left != right && left
        }
    }

    func isFormPinned(_ id: String) -> Bool { state.strings("pinnedForms").contains(id) }

    @discardableResult
    func toggleFormPinned(_ id: String) throws -> Bool {
        var pinned = state.strings("pinnedForms")
        if let index = pinned.firstIndex(of: id) { pinned.remove(at: index) }
        else { pinned.append(id) }
        state["pinnedForms"] = pinned
        try persist()
        return pinned.contains(id)
    }

    func isCategoryCollapsed(_ category: String) -> Bool {
        state.strings("collapsedFormCategories").contains(category)
    }

    func toggleCategory(_ category: String) throws {
        var collapsed = state.strings("collapsedFormCategories")
        if let index = collapsed.firstIndex(of: category) { collapsed.remove(at: index) }
        else { collapsed.append(category) }
        state["collapsedFormCategories"] = collapsed
        try persist()
    }

    func draft(id: String) -> JSONObject? { draftMap[id].map(JSONCopy.object) }
    func newDraftID() -> String { UUID().uuidString }

    func saveDraft(id: String, formID: String, values: JSONObject, createdAt: Int64,
                   population: JSONObject?) throws {
        var drafts = draftMap
        let existing = drafts[id]
        guard let form = existing?.object("form") ?? form(id: formID) else { return }
        var item = existing ?? [:]
        item["localId"] = id
        item["uuid"] = existing?["uuid"] ?? NSNull()
        item["formId"] = formID
        item["title"] = form.string("name", default: "Form")
        item["form"] = JSONCopy.object(form)
        item["createdAt"] = createdAt
        item["updatedAt"] = nowMilliseconds()
        item["values"] = JSONCopy.object(values)
        item["attachments"] = (existing?["attachments"] as? [Any]) ?? []
        item["populationSnapshot"] = population.map(JSONCopy.object) ?? NSNull()
        item["dirty"] = true
        drafts[id] = item
        state["drafts"] = drafts
        try persist()
    }

    func discardDraft(id: String, checkpoint: JSONObject?) throws {
        var drafts = draftMap
        if var restored = checkpoint {
            if let uuid = drafts[id]?["uuid"], !(uuid is NSNull) { restored["uuid"] = uuid }
            restored["updatedAt"] = nowMilliseconds()
            drafts[id] = restored
        } else {
            drafts.removeValue(forKey: id)
        }
        state["drafts"] = drafts
        try persist()
    }

    @discardableResult
    func deleteAllDrafts() throws -> Int {
        let drafts = draftMap
        guard !drafts.isEmpty else { return 0 }
        var deleted = deletedDraftMap
        for (id, draft) in drafts {
            let uuid = draft.string("uuid")
            deleted[id] = uuid.isEmpty ? NSNull() : uuid
        }
        state["drafts"] = [String: Any]()
        state["deletedDrafts"] = deleted
        try persist()
        return drafts.count
    }

    var pendingDraftDeletionUUIDs: [String] {
        Array(Set(deletedDraftMap.values.compactMap { value in
            guard !(value is NSNull) else { return nil }
            let uuid = String(describing: value)
            return uuid.isEmpty ? nil : uuid
        }))
    }

    func markDraftDeletionSynced(uuid: String) throws {
        state["deletedDrafts"] = deletedDraftMap.filter { String(describing: $0.value) != uuid }
        try persist()
    }

    func queueDraft(id: String) throws {
        var drafts = draftMap
        guard var item = drafts[id] else { throw StoreError.unknownDraft }
        item["queuedAt"] = nowMilliseconds()
        item["payload"] = try payload(for: item, status: "outbox")
        var queue = state.objects("outbox")
        queue.append(item)
        drafts.removeValue(forKey: id)
        state["outbox"] = queue
        state["drafts"] = drafts
        try persist()
    }

    var dirtyDrafts: JSONArray {
        draftMap.values.compactMap { draft in
            guard draft.bool("dirty"), let payload = try? payload(for: draft, status: "draft") else { return nil }
            var item = JSONCopy.object(draft)
            item["payload"] = payload
            return item
        }
    }

    func dirtyDraft(id: String) -> JSONObject? {
        guard let draft = draftMap[id], draft.bool("dirty"),
              let payload = try? payload(for: draft, status: "draft") else { return nil }
        var item = JSONCopy.object(draft)
        item["payload"] = payload
        return item
    }

    func markDraftSynced(id: String, uuid: String, syncedUpdatedAt: Int64) throws {
        var deleted = deletedDraftMap
        if deleted[id] != nil {
            deleted[id] = uuid
            state["deletedDrafts"] = deleted
            try persist()
            return
        }
        var drafts = draftMap
        guard var draft = drafts[id] else { return }
        draft["uuid"] = uuid
        if draft.milliseconds("updatedAt") == syncedUpdatedAt { draft["dirty"] = false }
        drafts[id] = draft
        state["drafts"] = drafts
        try persist()
    }

    func rememberOutboxUUID(localID: String, uuid: String) throws {
        var queue = state.objects("outbox")
        guard let index = queue.firstIndex(where: { $0.string("localId") == localID }) else { return }
        queue[index]["uuid"] = uuid
        if var payload = queue[index].object("payload") {
            payload["uuid"] = uuid
            queue[index]["payload"] = payload
        }
        state["outbox"] = queue
        try persist()
    }

    func markOutboxSent(localID: String, uuid: String) throws {
        var completed: JSONObject?
        let kept = state.objects("outbox").filter {
            if $0.string("localId") == localID { completed = $0; return false }
            return true
        }
        state["outbox"] = kept
        if var completed {
            var sentHeaders = state.objects("sent")
            sentHeaders.append([
                "uuid": uuid,
                "formId": completed.string("formId"),
                "formName": completed.string("title"),
                "lastModifiedAt": nowMilliseconds()
            ])
            state["sent"] = sentHeaders
            completed["uuid"] = uuid
            completed["dirty"] = false
            var cached = sentSubmissionMap
            cached[uuid] = completed
            state["sentSubmissions"] = cached
        }
        try persist()
    }

    func sentSubmission(uuid: String) -> JSONObject? { sentSubmissionMap[uuid].map(JSONCopy.object) }
    func outboxSubmission(id: String) -> JSONObject? {
        if let local = localOutbox.first(where: { $0.string("localId") == id || $0.string("uuid") == id }) {
            return JSONCopy.object(local)
        }
        return outboxSubmissionMap[id].map(JSONCopy.object)
    }

    func cacheSentSubmission(_ bundle: JSONObject) throws {
        guard let item = submission(from: bundle, workspace: "Submitted form") else { throw StoreError.invalidSubmission }
        var cached = sentSubmissionMap
        cached[item.string("uuid")] = item
        state["sentSubmissions"] = cached
        try persist()
    }

    func cacheOutboxSubmission(_ bundle: JSONObject) throws {
        guard let item = submission(from: bundle, workspace: "Outbox form") else { throw StoreError.invalidSubmission }
        var cached = outboxSubmissionMap
        cached[item.string("uuid")] = item
        state["outboxSubmissions"] = cached
        try persist()
    }

    func mergeRemote(forms: JSONArray, draftBundles: JSONArray,
                     serverOutbox: JSONArray, sent: JSONArray) throws {
        let existing = draftMap
        var merged = existing.filter { $0.value.bool("dirty") || $0.value.string("uuid").isEmpty }
        for bundle in draftBundles {
            guard var item = submission(from: bundle, workspace: "Downloaded draft") else { continue }
            let uuid = item.string("uuid")
            if pendingDraftDeletionUUIDs.contains(uuid) { continue }
            if merged.values.contains(where: { $0.string("uuid") == uuid && $0.bool("dirty") }) { continue }
            let stableID = existing.first(where: { $0.value.string("uuid") == uuid })?.key ?? uuid
            item["localId"] = stableID
            merged[stableID] = item
        }
        state["forms"] = JSONCopy.array(forms)
        state["drafts"] = merged
        state["serverOutbox"] = JSONCopy.array(serverOutbox)
        state["sent"] = JSONCopy.array(sent)
        state["lastSync"] = nowMilliseconds()
        try persist()
    }

    var canStartReviewDemo: Bool {
        let hash = state.string("accountHash")
        if hash == SessionStore.demoAccountHash { return true }
        return hash.isEmpty && forms.isEmpty && drafts.isEmpty && outbox.isEmpty && sent.isEmpty
    }

    func startReviewDemo(now: Date = Date()) throws {
        guard canStartReviewDemo else { throw StoreError.existingAccountData }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_GB")
        formatter.dateFormat = "dd-MM-yyyy_HH-mm"
        func population(_ id: String, _ date: Date, _ title: String) -> JSONObject {
            ["id": id, "name": "\(formatter.string(from: date))_\(title)", "tokenMap": JSONObject()]
        }
        let populations: JSONArray = [
            population("demo-overdue", Calendar.current.date(byAdding: .day, value: -1, to: now)!, "Ward teaching"),
            population("demo-soon", now.addingTimeInterval(45 * 60), "Clinical skills teaching"),
            population("demo-future", Calendar.current.date(byAdding: .day, value: 1, to: now)!, "Tutorial")
        ]
        let form: JSONObject = [
            "id": "review-demo-attendance", "version": 1,
            "name": "Example placement attendance", "workspaceName": "Play review examples",
            "requirePopulation": true,
            "populationSets": [["id": "demo-attendance-sessions", "name": "Attendance sessions", "populations": populations]],
            "fields": [
                ["id": "section", "type": "section", "title": "Placement details"],
                ["id": "student", "type": "textbox", "name": "studentName", "title": "Student name", "required": true, "defaultValue": "Demo Student"],
                ["id": "date", "type": "date", "name": "placementDate", "title": "Attendance date", "required": true],
                ["id": "reflection", "type": "textarea", "name": "reflection", "title": "Brief reflection"],
                ["id": "signature", "type": "signature", "name": "signature", "title": "Example signature", "required": true]
            ] as JSONArray
        ]
        state = Self.freshState()
        state["accountHash"] = SessionStore.demoAccountHash
        state["forms"] = [form]
        try persist()
    }

    func clearAccountData() throws {
        state = Self.freshState()
        try vault.clear()
        storageFailure = nil
        revision += 1
    }

    private var draftMap: [String: JSONObject] { state["drafts"] as? [String: JSONObject] ?? [:] }
    private var deletedDraftMap: [String: Any] { state["deletedDrafts"] as? [String: Any] ?? [:] }
    private var sentSubmissionMap: [String: JSONObject] { state["sentSubmissions"] as? [String: JSONObject] ?? [:] }
    private var outboxSubmissionMap: [String: JSONObject] { state["outboxSubmissions"] as? [String: JSONObject] ?? [:] }

    private func payload(for draft: JSONObject, status: String) throws -> JSONObject {
        guard let form = draft.object("form") ?? form(id: draft.string("formId")) else { throw StoreError.missingForm }
        return [
            "uuid": draft.string("uuid").isEmpty ? NSNull() : draft.string("uuid"),
            "createdAt": draft.milliseconds("createdAt"),
            "status": status,
            "data": draft.object("values") ?? JSONObject(),
            "attachments": draft["attachments"] as? [Any] ?? [],
            "formSnapshot": ["id": form["id"] ?? "", "version": form.integer("version"), "name": form.string("name")],
            "populationSnapshot": draft["populationSnapshot"] ?? NSNull(),
            "fields": form.objects("fields")
        ]
    }

    private func submission(from bundle: JSONObject, workspace: String) -> JSONObject? {
        guard let submission = bundle.object("submission") else { return nil }
        let uuid = submission.string("uuid")
        guard !uuid.isEmpty,
              let snapshot = bundle.object("formSnapshot") ?? submission.object("formSnapshot") else { return nil }
        var form = snapshot
        form["workspaceName"] = workspace
        form["requirePopulation"] = false
        form["populationSets"] = JSONArray()
        form["fields"] = bundle.objects("fields").isEmpty ? submission.objects("fields") : bundle.objects("fields")
        return [
            "localId": uuid, "uuid": uuid, "formId": snapshot.string("id"),
            "title": snapshot.string("name", default: "Form"), "form": form,
            "createdAt": submission.milliseconds("createdAt"), "updatedAt": nowMilliseconds(),
            "values": submission.object("data") ?? JSONObject(),
            "attachments": submission["attachments"] as? [Any] ?? [],
            "populationSnapshot": submission["populationSnapshot"] ?? NSNull(), "dirty": false
        ]
    }

    private func persist() throws {
        if storageFailure != nil { throw StoreError.vaultUnavailable }
        try vault.save(state)
        revision += 1
    }

    private static func freshState() -> JSONObject {
        [
            "schemaVersion": schemaVersion, "accountHash": "", "forms": JSONArray(),
            "pinnedForms": [String](), "collapsedFormCategories": [String](),
            "drafts": [String: JSONObject](), "deletedDrafts": [String: Any](),
            "outbox": JSONArray(), "serverOutbox": JSONArray(),
            "outboxSubmissions": [String: JSONObject](), "sent": JSONArray(),
            "sentSubmissions": [String: JSONObject](), "lastSync": Int64(0)
        ]
    }
}

enum StoreError: LocalizedError {
    case invalidAccount, unknownDraft, invalidSubmission, missingForm, existingAccountData, vaultUnavailable
    var errorDescription: String? {
        switch self {
        case .invalidAccount: return "An account identity is required."
        case .unknownDraft: return "The draft is no longer available."
        case .invalidSubmission: return "The downloaded form is incomplete."
        case .missingForm: return "This form is no longer available."
        case .existingAccountData: return "Review data cannot replace existing offline account data."
        case .vaultUnavailable: return "The encrypted offline vault is unavailable. Log out to erase it before saving new work."
        }
    }
}

import Foundation

struct SyncResult {
    let ok: Bool
    let authRequired: Bool
    let submitted: Int
    let message: String
}

@MainActor
final class SyncEngine {
    static let shared = SyncEngine()
    private let store = AppStore.shared
    private let session = SessionStore.shared
    private let api = ManchesterAPI.shared

    func run() async -> SyncResult {
        if session.isReviewDemo { return SyncResult(ok: true, authRequired: false, submitted: 0, message: "Review demo data stays on this device.") }
        guard session.isSyncAuthorized else { return SyncResult(ok: false, authRequired: true, submitted: 0, message: "Confirm your University account before syncing.") }
        guard NetworkMonitor.shared.isOnline else { return SyncResult(ok: false, authRequired: false, submitted: 0, message: "Offline — downloaded forms and changes are safe on this device.") }
        await session.refreshCookieState()
        guard session.hasSession else { return SyncResult(ok: false, authRequired: true, submitted: 0, message: "Sign in to Manchester eForms to sync.") }

        do {
            let pushed = try await pushPending()
            let forms = try await api.assignedForms()
            let draftHeaders = try await api.headers("drafts")
            var draftBundles: JSONArray = []
            for header in draftHeaders {
                let uuid = header.string("uuid")
                if !uuid.isEmpty { draftBundles.append(try await api.submission(uuid)) }
            }
            let remoteOutbox = try await api.headers("outbox")
            let sent = try await api.headers("sent")
            try store.mergeRemote(forms: forms, draftBundles: draftBundles,
                                  serverOutbox: remoteOutbox, sent: sent)
            let message: String
            if pushed.submitted > 0 { message = "\(pushed.submitted) form(s) submitted." }
            else if pushed.deleted > 0 { message = "\(pushed.deleted) draft(s) deleted from Manchester eForms." }
            else if pushed.drafts > 0 { message = "\(pushed.drafts) draft(s) saved in eForms Drafts." }
            else { message = "\(forms.count) assigned forms available offline." }
            return SyncResult(ok: true, authRequired: false, submitted: pushed.submitted, message: message)
        } catch APIError.notAuthenticated {
            session.isSyncAuthorized = false
            return SyncResult(ok: false, authRequired: true, submitted: 0, message: APIError.notAuthenticated.localizedDescription)
        } catch {
            return SyncResult(ok: false, authRequired: false, submitted: 0, message: error.localizedDescription)
        }
    }

    func saveDraft(id: String) async -> SyncResult {
        if session.isReviewDemo { return SyncResult(ok: true, authRequired: false, submitted: 0, message: "Saved locally in the review demo.") }
        guard session.isSyncAuthorized else { return SyncResult(ok: false, authRequired: true, submitted: 0, message: "Saved on this device — confirm your account before syncing.") }
        guard NetworkMonitor.shared.isOnline else { return SyncResult(ok: false, authRequired: false, submitted: 0, message: "Saved on this device — it will sync when you are online.") }
        await session.refreshCookieState()
        guard session.hasSession else { return SyncResult(ok: false, authRequired: true, submitted: 0, message: "Saved on this device — sign in to sync it.") }
        guard let draft = store.dirtyDraft(id: id), let payload = draft.object("payload") else {
            return SyncResult(ok: true, authRequired: false, submitted: 0, message: "Already saved in eForms Drafts.")
        }
        do {
            let uuid = try await api.save(payload)
            try store.markDraftSynced(id: id, uuid: uuid, syncedUpdatedAt: draft.milliseconds("updatedAt"))
            return SyncResult(ok: true, authRequired: false, submitted: 0, message: "Saved in Manchester eForms Drafts.")
        } catch APIError.notAuthenticated {
            session.isSyncAuthorized = false
            return SyncResult(ok: false, authRequired: true, submitted: 0, message: "Saved locally — sign in to sync it.")
        } catch {
            return SyncResult(ok: false, authRequired: false, submitted: 0, message: "Saved locally — eForms sync will retry automatically.")
        }
    }

    func downloadSent(uuid: String) async -> SyncResult {
        if store.sentSubmission(uuid: uuid) != nil { return SyncResult(ok: true, authRequired: false, submitted: 0, message: "Submitted form available offline.") }
        return await download(uuid: uuid, outbox: false)
    }

    func downloadOutbox(uuid: String) async -> SyncResult {
        if store.outboxSubmission(id: uuid) != nil { return SyncResult(ok: true, authRequired: false, submitted: 0, message: "Outbox form available offline.") }
        return await download(uuid: uuid, outbox: true)
    }

    private func download(uuid: String, outbox: Bool) async -> SyncResult {
        guard !session.isReviewDemo else { return SyncResult(ok: false, authRequired: false, submitted: 0, message: "Server forms are not included in the review demo.") }
        guard session.isSyncAuthorized else { return SyncResult(ok: false, authRequired: true, submitted: 0, message: "Confirm your account first.") }
        guard NetworkMonitor.shared.isOnline else { return SyncResult(ok: false, authRequired: false, submitted: 0, message: "Connect once to download this form for offline viewing.") }
        do {
            let bundle = try await api.submission(uuid)
            if outbox { try store.cacheOutboxSubmission(bundle) } else { try store.cacheSentSubmission(bundle) }
            return SyncResult(ok: true, authRequired: false, submitted: 0, message: "Form downloaded for offline viewing.")
        } catch APIError.notAuthenticated {
            session.isSyncAuthorized = false
            return SyncResult(ok: false, authRequired: true, submitted: 0, message: APIError.notAuthenticated.localizedDescription)
        } catch {
            return SyncResult(ok: false, authRequired: false, submitted: 0, message: error.localizedDescription)
        }
    }

    private func pushPending() async throws -> (submitted: Int, drafts: Int, deleted: Int) {
        var deleted = 0
        for uuid in store.pendingDraftDeletionUUIDs {
            try await api.deleteDraft(uuid)
            try store.markDraftDeletionSynced(uuid: uuid)
            deleted += 1
        }
        var drafts = 0
        for item in store.dirtyDrafts {
            guard let payload = item.object("payload") else { continue }
            let uuid = try await api.save(payload)
            try store.markDraftSynced(id: item.string("localId"), uuid: uuid,
                                      syncedUpdatedAt: item.milliseconds("updatedAt"))
            drafts += 1
        }
        var submitted = 0
        for item in store.localOutbox {
            guard let payload = item.object("payload") else { continue }
            let uuid = try await api.save(payload)
            try store.rememberOutboxUUID(localID: item.string("localId"), uuid: uuid)
            try await api.promote(uuid)
            try store.markOutboxSent(localID: item.string("localId"), uuid: uuid)
            submitted += 1
        }
        return (submitted, drafts, deleted)
    }
}

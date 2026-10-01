import Foundation
import WidgetKit

@MainActor
final class AppModel: ObservableObject {
    enum Folder: String, CaseIterable, Identifiable {
        case forms = "Forms", drafts = "Drafts", outbox = "Outbox", sent = "Sent"
        var id: String { rawValue }
    }

    static let shared = AppModel()

    let store = AppStore.shared
    let session = SessionStore.shared
    let network = NetworkMonitor.shared

    @Published var eulaAccepted = LegalAcceptance.isAccepted
    @Published var activeFolder: Folder = .forms
    @Published var search = ""
    @Published var syncing = false
    @Published var showLogin = false
    @Published var showAccountConfirmation = false
    @Published var showAttendance = false
    @Published var showAccountMismatch = false
    @Published var message: String?
    @Published private(set) var attendance = AttendanceSnapshot(available: false, entries: [], level: .green, incompleteCount: 0)

    private init() {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--ui-testing") {
            try? store.clearAccountData()
            try? store.startReviewDemo()
            session.isReviewDemo = true
            LegalAcceptance.accept()
            eulaAccepted = true
            attendance = AttendanceRules.build(store: store)
        }
        #endif
    }
    private var replacementAccountHash: String?

    func start() async {
        if let failure = store.storageFailure { message = failure }
        await session.refreshCookieState()
        updateAttendance()
        if session.isReviewDemo {
            if !store.isBound(to: SessionStore.demoAccountHash) { try? store.startReviewDemo() }
        } else if !session.hasSession {
            showLogin = true
        } else if session.accountConfirmationPending || !store.hasAccountBinding {
            showAccountConfirmation = true
        } else if !session.isSyncAuthorized {
            showLogin = true
        } else {
            await automaticRefreshIfDue()
        }
        BackgroundRefresh.schedule()
    }

    func acceptEULA() {
        LegalAcceptance.accept()
        eulaAccepted = true
    }

    func loginFinished() async {
        await session.refreshCookieState()
        showLogin = false
        guard session.hasSession else { return }
        session.accountConfirmationPending = true
        showAccountConfirmation = true
    }

    func confirmAccount(username: String) async -> Bool {
        guard let hash = session.accountHash(username) else {
            message = "Enter a valid University username."
            return false
        }
        do {
            if try store.bindAccount(hash) {
                session.accountConfirmationPending = false
                session.isSyncAuthorized = true
                showAccountConfirmation = false
                await refresh(manual: false)
                return true
            }
            replacementAccountHash = hash
            showAccountConfirmation = false
            showAccountMismatch = true
            return false
        } catch {
            message = error.localizedDescription
            return false
        }
    }

    func eraseForDifferentAccount() async {
        guard let hash = replacementAccountHash else { return }
        do {
            try store.replaceAccount(with: hash)
            session.accountConfirmationPending = false
            session.isSyncAuthorized = true
            showAccountMismatch = false
            showAccountConfirmation = false
            replacementAccountHash = nil
            updateAttendance()
            await refresh(manual: false)
        } catch {
            message = error.localizedDescription
        }
    }

    func refresh(manual: Bool = true) async {
        guard !syncing else { return }
        if session.isReviewDemo {
            updateAttendance()
            if manual { message = "Review demo data stays on this device." }
            return
        }
        guard store.hasAccountBinding else { showAccountConfirmation = true; return }
        syncing = true
        let result = await SyncEngine.shared.run()
        syncing = false
        if manual || result.authRequired || !result.ok { message = result.message }
        if result.ok { session.recordAutomaticRefresh() }
        if result.authRequired { showLogin = true }
        updateAttendance()
        BackgroundRefresh.schedule()
    }

    func automaticRefreshIfDue() async {
        guard session.automaticRefreshDue(), network.isOnline, session.isSyncAuthorized else {
            updateAttendance()
            return
        }
        session.recordAutomaticRefresh()
        await refresh(manual: false)
    }

    func startReviewDemo() {
        do {
            try store.startReviewDemo()
            session.isReviewDemo = true
            showLogin = false
            updateAttendance()
        } catch {
            message = error.localizedDescription
        }
    }

    func logout() async {
        BackgroundRefresh.cancel()
        await session.clearWebSession()
        do { try store.clearAccountData() }
        catch { message = "Local data could not be completely erased: \(error.localizedDescription)" }
        LegalAcceptance.clear()
        eulaAccepted = false
        activeFolder = .forms
        search = ""
        showLogin = false
        showAccountConfirmation = false
        AttendanceWidgetSnapshot.clear()
        WidgetCenter.shared.reloadAllTimelines()
        attendance = AttendanceSnapshot(available: false, entries: [], level: .green, incompleteCount: 0)
    }

    func updateAttendance() {
        attendance = AttendanceRules.build(store: store)
        AttendanceWidgetSnapshot(
            available: attendance.available,
            sessions: attendance.entries.map { AttendanceWidgetSession(startsAt: $0.startsAt, completed: $0.completed) },
            lastUpdated: Date()
        ).save()
        WidgetCenter.shared.reloadAllTimelines()
    }

    func open(url: URL) {
        if url.scheme == "eforms", url.host == "attendance" { showAttendance = true }
    }
}

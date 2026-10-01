import BackgroundTasks
import Foundation

enum BackgroundRefresh {
    static let refreshID = "app.offlineform.companion.ios.refresh"
    static let outboxID = "app.offlineform.companion.ios.outbox"

    static func register() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: refreshID, using: nil) { task in
            guard let task = task as? BGAppRefreshTask else { return }
            handle(task)
        }
        BGTaskScheduler.shared.register(forTaskWithIdentifier: outboxID, using: nil) { task in
            guard let task = task as? BGProcessingTask else { return }
            handle(task)
        }
    }

    static func schedule() {
        let refresh = BGAppRefreshTaskRequest(identifier: refreshID)
        refresh.earliestBeginDate = Date(timeIntervalSinceNow: 3_600)
        try? BGTaskScheduler.shared.submit(refresh)

        Task { @MainActor in
            let store = AppStore.shared
            guard !store.localOutbox.isEmpty || !store.dirtyDrafts.isEmpty || !store.pendingDraftDeletionUUIDs.isEmpty else { return }
            let processing = BGProcessingTaskRequest(identifier: outboxID)
            processing.requiresNetworkConnectivity = true
            processing.requiresExternalPower = false
            processing.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)
            try? BGTaskScheduler.shared.submit(processing)
        }
    }

    static func cancel() {
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: refreshID)
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: outboxID)
    }

    private static func handle(_ task: BGTask) {
        schedule()
        let completion = BackgroundTaskCompletion(task)
        let work = Task { @MainActor in
            await SessionStore.shared.refreshCookieState()
            if SessionStore.shared.automaticRefreshDue(), SessionStore.shared.hasSession,
               SessionStore.shared.isSyncAuthorized, NetworkMonitor.shared.isOnline {
                SessionStore.shared.recordAutomaticRefresh()
                _ = await SyncEngine.shared.run()
            }
            AppModel.shared.updateAttendance()
            completion.finish(success: true)
        }
        task.expirationHandler = {
            work.cancel()
            completion.finish(success: false)
        }
    }
}

private final class BackgroundTaskCompletion {
    private let task: BGTask
    private let lock = NSLock()
    private var finished = false

    init(_ task: BGTask) { self.task = task }

    func finish(success: Bool) {
        lock.lock()
        defer { lock.unlock() }
        guard !finished else { return }
        finished = true
        task.setTaskCompleted(success: success)
    }
}

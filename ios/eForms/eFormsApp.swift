import SwiftUI
import UIKit
#if canImport(FirebaseCore)
import FirebaseCore
import FirebaseCrashlytics
#endif

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        BackgroundRefresh.register()
        #if canImport(FirebaseCore)
        if Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist") != nil {
            FirebaseApp.configure()
            Crashlytics.crashlytics().setCrashlyticsCollectionEnabled(true)
        }
        #endif
        return true
    }

    func applicationDidEnterBackground(_ application: UIApplication) {
        BackgroundRefresh.schedule()
    }
}

@main
struct eFormsApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = AppModel.shared
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(model)
                .task { await model.start() }
                .onOpenURL { model.open(url: $0) }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await model.automaticRefreshIfDue() } }
            if phase == .background { BackgroundRefresh.schedule() }
        }
    }
}

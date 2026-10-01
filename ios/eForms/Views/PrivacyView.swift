import SwiftUI

struct PrivacyView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var model: AppModel
    @State private var reviewMessage: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Privacy & data use").font(.title2.weight(.semibold))
                section("Independent app", "eForms is independently developed and is not affiliated with, endorsed by or published by the University of Manchester.")
                section("Sign-in", "Sign-in takes place on the service and University authentication pages in an in-app browser. The app does not ask for, copy or store your password. Session cookies remain in Apple’s WebKit website-data store.")
                section("Offline data", "Downloaded forms, drafts, Outbox items, submitted-form copies, pins and synchronisation status are encrypted on this device with a non-exportable Keychain-protected key. App data is excluded from normal backup.")
                section("Network use", "When you refresh, save or submit, the app communicates directly with the Manchester eForms HTTPS service using your authenticated session. No developer-operated relay server is used.")
                section("Widgets", "The attendance widget stores only encrypted session start times, completion states and the last update time in the app’s private shared container. It does not store session titles, answers, signatures or your username.")
                section("Crash reports", "Release builds may use Apple or Firebase technical crash reporting if configured by the publisher. Form answers, signatures, credentials and University usernames must not be deliberately attached to reports.")
                section("Logout", "Log out removes this app’s downloaded forms, drafts, Outbox, sent-form copies, pins, cookies, encrypted vault and local encryption key. It does not delete anything from Manchester eForms online.")
                section("Important", "Do not rely on the app as the only record of deadline-critical submissions. Reconnect and verify important forms in the official service.")

                Button("Open App Review demo") {
                    if model.eulaAccepted { model.startReviewDemo(); dismiss() }
                    else { reviewMessage = "Accept the EULA before opening the App Review demo." }
                }
                    .buttonStyle(CompactButtonStyle(primary: false))
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, 20)
            }
            .padding(18)
        }
        .navigationTitle("Privacy")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        .alert("App Review demo", isPresented: Binding(
            get: { reviewMessage != nil }, set: { if !$0 { reviewMessage = nil } }
        )) { Button("OK") { reviewMessage = nil } } message: { Text(reviewMessage ?? "") }
    }

    @ViewBuilder private func section(_ title: String, _ text: String) -> some View {
        Text(title).font(.headline).foregroundStyle(AppTheme.deep)
        Text(text).foregroundStyle(AppTheme.ink)
    }
}

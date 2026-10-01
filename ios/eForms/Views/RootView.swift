import SwiftUI

struct RootView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Group {
            if model.eulaAccepted { MainView() }
            else { EULAView() }
        }
        .tint(AppTheme.purple)
    }
}


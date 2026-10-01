import SwiftUI
import WebKit

struct PortalView: View {
    enum Mode: Equatable { case login, dashboard, home }
    @Environment(\.dismiss) private var dismiss
    let mode: Mode
    var required = false
    var loginCompleted: (() -> Void)?
    @State private var showPrivacy = false

    var body: some View {
        NavigationStack {
            SecureWebContainer(
                initialURL: mode == .login || mode == .home ? SessionStore.home : SessionStore.dashboards,
                loginMode: mode == .login,
                loginCompleted: {
                    loginCompleted?()
                    dismiss()
                }
            )
            .ignoresSafeArea(.container, edges: .bottom)
            .navigationTitle(mode == .login ? "Sign in" : mode == .dashboard ? "My Dashboards" : "Online eForms")
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if mode == .login {
                    Button("Privacy & data use") { showPrivacy = true }
                        .font(.caption).frame(maxWidth: .infinity).padding(.vertical, 8)
                        .background(.thinMaterial)
                }
            }
            .toolbar {
                if !required { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
            }
        }
        .sheet(isPresented: $showPrivacy) { NavigationStack { PrivacyView() } }
    }
}

private struct SecureWebContainer: UIViewRepresentable {
    let initialURL: URL
    let loginMode: Bool
    let loginCompleted: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeUIView(context: Context) -> WebHostView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = true
        configuration.mediaTypesRequiringUserActionForPlayback = .all
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        webView.isInspectable = false
        webView.scrollView.keyboardDismissMode = .interactive
        let host = WebHostView(main: webView)
        context.coordinator.host = host
        webView.load(URLRequest(url: initialURL, cachePolicy: .reloadIgnoringLocalCacheData))
        return host
    }

    func updateUIView(_ uiView: WebHostView, context: Context) {}

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        let parent: SecureWebContainer
        weak var host: WebHostView?
        private var popup: WKWebView?
        private var completionSent = false

        init(parent: SecureWebContainer) { self.parent = parent }

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard let url = navigationAction.request.url else { decisionHandler(.cancel); return }
            guard url.scheme?.lowercased() == "https" else {
                if !["about", "data"].contains(url.scheme?.lowercased() ?? "") {
                    Task { @MainActor in UIApplication.shared.open(url) }
                }
                decisionHandler(["about", "data"].contains(url.scheme?.lowercased() ?? "") ? .allow : .cancel)
                return
            }
            if !parent.loginMode, url.host?.lowercased() != SessionStore.origin.host?.lowercased() {
                Task { @MainActor in UIApplication.shared.open(url) }
                decisionHandler(.cancel)
                return
            }
            decisionHandler(.allow)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            if parent.loginMode { detectCompletedLogin(webView.url) }
            else { applyDashboardStyles(webView) }
        }

        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                     for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
            guard let host else { return nil }
            let popup = WKWebView(frame: host.bounds, configuration: configuration)
            popup.navigationDelegate = self
            popup.uiDelegate = self
            popup.isInspectable = false
            popup.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            host.addSubview(popup)
            self.popup = popup
            if let url = navigationAction.request.url { popup.load(URLRequest(url: url)) }
            return popup
        }

        func webViewDidClose(_ webView: WKWebView) {
            if webView == popup { popup?.removeFromSuperview(); popup = nil }
        }

        private func detectCompletedLogin(_ url: URL?) {
            guard !completionSent, url?.host?.lowercased() == SessionStore.origin.host?.lowercased(),
                  url?.path.hasPrefix("/ui") == true else { return }
            Task { @MainActor in
                await SessionStore.shared.refreshCookieState()
                if SessionStore.shared.hasSession, !completionSent {
                    completionSent = true
                    parent.loginCompleted()
                }
            }
        }

        private func applyDashboardStyles(_ webView: WKWebView) {
            let css = """
            html,body{max-width:100%!important;overflow-x:hidden!important}
            .sidebar,.left-sidebar{position:relative!important;width:100%!important;max-width:100%!important}
            .grid-stack{height:auto!important;display:flex!important;flex-direction:column!important}
            .grid-stack-item{position:relative!important;transform:none!important;left:auto!important;top:auto!important;width:100%!important;height:auto!important;min-height:160px!important;margin-bottom:10px!important}
            .widget,.widget .content{width:100%!important;max-width:100%!important;box-sizing:border-box!important}
            .sourcetable-widget,.table-responsive{overflow-x:auto!important;-webkit-overflow-scrolling:touch!important}
            .widget canvas{max-width:100%!important}
            """
            let script = "var s=document.createElement('style');s.textContent=\(javascriptString(css));document.head.appendChild(s);"
            webView.evaluateJavaScript(script)
        }

        private func javascriptString(_ value: String) -> String {
            guard let data = try? JSONSerialization.data(withJSONObject: [value]),
                  let json = String(data: data, encoding: .utf8) else { return "''" }
            return String(json.dropFirst().dropLast())
        }
    }
}

private final class WebHostView: UIView {
    let main: WKWebView
    init(main: WKWebView) {
        self.main = main
        super.init(frame: .zero)
        main.translatesAutoresizingMaskIntoConstraints = false
        addSubview(main)
        NSLayoutConstraint.activate([
            main.leadingAnchor.constraint(equalTo: leadingAnchor),
            main.trailingAnchor.constraint(equalTo: trailingAnchor),
            main.topAnchor.constraint(equalTo: topAnchor),
            main.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }
    required init?(coder: NSCoder) { nil }
}

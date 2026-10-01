import CryptoKit
import Foundation
import WebKit

@MainActor
final class SessionStore: ObservableObject {
    static let shared = SessionStore()
    static let origin = URL(string: "https://www.onemedforms.manchester.ac.uk")!
    static let home = URL(string: "https://www.onemedforms.manchester.ac.uk/ui")!
    static let dashboards = URL(string: "https://www.onemedforms.manchester.ac.uk/dashboards")!
    static let demoAccountHash = "review-demo-account-v1"

    private enum Key {
        static let reviewDemo = "reviewDemo"
        static let syncAuthorized = "syncAuthorized"
        static let accountConfirmationPending = "accountConfirmationPending"
        static let lastAutomaticRefresh = "lastAutomaticRefreshAt"
    }

    private let defaults = UserDefaults.standard
    @Published private(set) var hasSession = false

    var isReviewDemo: Bool {
        get { defaults.bool(forKey: Key.reviewDemo) }
        set {
            defaults.set(newValue, forKey: Key.reviewDemo)
            if newValue {
                defaults.set(false, forKey: Key.syncAuthorized)
                defaults.set(false, forKey: Key.accountConfirmationPending)
            }
        }
    }

    var isSyncAuthorized: Bool {
        get { !isReviewDemo && defaults.bool(forKey: Key.syncAuthorized) }
        set { defaults.set(newValue, forKey: Key.syncAuthorized) }
    }

    var accountConfirmationPending: Bool {
        get { defaults.bool(forKey: Key.accountConfirmationPending) }
        set { defaults.set(newValue, forKey: Key.accountConfirmationPending) }
    }

    func automaticRefreshDue(at date: Date = Date()) -> Bool {
        let last = defaults.double(forKey: Key.lastAutomaticRefresh)
        return last <= 0 || date.timeIntervalSince1970 < last || date.timeIntervalSince1970 - last >= 3_600
    }

    func recordAutomaticRefresh(at date: Date = Date()) {
        defaults.set(date.timeIntervalSince1970, forKey: Key.lastAutomaticRefresh)
    }

    func refreshCookieState() async {
        hasSession = await cookieHeader().split(separator: ";").contains {
            String($0).trimmingCharacters(in: .whitespaces).uppercased().hasPrefix("PLAY_SESSION=")
        }
    }

    func cookieHeader() async -> String {
        await withCheckedContinuation { continuation in
            WKWebsiteDataStore.default().httpCookieStore.getAllCookies { cookies in
                let host = Self.origin.host ?? ""
                let matching = cookies.filter { cookie in
                    host == cookie.domain.trimmingCharacters(in: CharacterSet(charactersIn: ".")) ||
                    host.hasSuffix("." + cookie.domain.trimmingCharacters(in: CharacterSet(charactersIn: ".")))
                }
                continuation.resume(returning: matching.map { "\($0.name)=\($0.value)" }.joined(separator: "; "))
            }
        }
    }

    func csrfToken() async -> String {
        let header = await cookieHeader()
        for component in header.split(separator: ";") {
            let pair = component.trimmingCharacters(in: .whitespaces).split(separator: "=", maxSplits: 1)
            guard pair.count == 2 else { continue }
            if ["XSRF-TOKEN", "CSRF-TOKEN"].contains(pair[0].uppercased()) {
                return String(pair[1]).removingPercentEncoding ?? String(pair[1])
            }
        }
        return ""
    }

    func acceptCookies(from response: HTTPURLResponse) async {
        guard let url = response.url else { return }
        let headers = response.allHeaderFields.reduce(into: [String: String]()) {
            $0[String(describing: $1.key)] = String(describing: $1.value)
        }
        let cookies = HTTPCookie.cookies(withResponseHeaderFields: headers, for: url)
        for cookie in cookies {
            await withCheckedContinuation { continuation in
                WKWebsiteDataStore.default().httpCookieStore.setCookie(cookie) { continuation.resume() }
            }
        }
        await refreshCookieState()
    }

    func accountHash(_ username: String) -> String? {
        var normalized = username.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let at = normalized.firstIndex(of: "@") {
            let domain = String(normalized[normalized.index(after: at)...])
            if domain == "manchester.ac.uk" || domain.hasSuffix(".manchester.ac.uk") {
                normalized = String(normalized[..<at])
            }
        }
        guard normalized.range(of: #"^[a-z0-9._-]{2,80}$"#, options: .regularExpression) != nil else { return nil }
        let digest = SHA256.hash(data: Data("offline-form-companion-account-v1:\(normalized)".utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    func clearWebSession() async {
        isReviewDemo = false
        isSyncAuthorized = false
        accountConfirmationPending = false
        defaults.removeObject(forKey: Key.lastAutomaticRefresh)
        let store = WKWebsiteDataStore.default()
        let records = await withCheckedContinuation { continuation in
            store.fetchDataRecords(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes()) { continuation.resume(returning: $0) }
        }
        await withCheckedContinuation { continuation in
            store.removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), for: records) { continuation.resume() }
        }
        HTTPCookieStorage.shared.cookies?.forEach(HTTPCookieStorage.shared.deleteCookie)
        hasSession = false
    }
}

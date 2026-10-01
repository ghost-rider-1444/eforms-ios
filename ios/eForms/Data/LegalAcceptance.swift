import Foundation

enum LegalAcceptance {
    static let currentVersion = "2026-09-22-v1"
    private static let acceptedVersion = "eforms.acceptedEulaVersion"
    private static let acceptedAt = "eforms.acceptedEulaAt"

    static var isAccepted: Bool { UserDefaults.standard.string(forKey: acceptedVersion) == currentVersion }

    static func accept() {
        UserDefaults.standard.set(currentVersion, forKey: acceptedVersion)
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: acceptedAt)
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: acceptedVersion)
        UserDefaults.standard.removeObject(forKey: acceptedAt)
    }
}


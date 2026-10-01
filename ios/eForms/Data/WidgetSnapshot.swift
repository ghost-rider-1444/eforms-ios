import CryptoKit
import Foundation
import Security

enum AttendanceLevel: String, Codable { case green, amber, red }

struct AttendanceWidgetSession: Codable {
    let startsAt: Date
    let completed: Bool
}

struct AttendanceWidgetSnapshot: Codable {
    static let suite = "group.app.offlineform.companion.ios"
    private static let service = "app.offlineform.companion.ios.widget-key"
    private static let account = "attendance-widget-v1"

    let available: Bool
    let sessions: [AttendanceWidgetSession]
    let lastUpdated: Date

    static func load() -> AttendanceWidgetSnapshot {
        guard let url = snapshotURL,
              let combined = try? Data(contentsOf: url),
              let key = try? loadOrCreateKey(create: false),
              let sealed = try? AES.GCM.SealedBox(combined: combined),
              let data = try? AES.GCM.open(sealed, using: key),
              let snapshot = try? JSONDecoder().decode(Self.self, from: data) else {
            return Self(available: false, sessions: [], lastUpdated: .distantPast)
        }
        return snapshot
    }

    func save() {
        guard let url = Self.snapshotURL,
              let clear = try? JSONEncoder().encode(self),
              let key = try? Self.loadOrCreateKey(create: true),
              let sealed = try? AES.GCM.seal(clear, using: key),
              let combined = sealed.combined else { return }
        try? combined.write(to: url, options: [.atomic, .completeFileProtectionUnlessOpen])
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var protectedURL = url
        try? protectedURL.setResourceValues(values)
    }

    static func clear() {
        if let url = snapshotURL { try? FileManager.default.removeItem(at: url) }
        var query = keyQuery
        if !accessGroup.isEmpty { query[kSecAttrAccessGroup as String] = accessGroup }
        SecItemDelete(query as CFDictionary)
    }

    func status(at now: Date = Date()) -> (AttendanceLevel, Int) {
        let incomplete = sessions.filter { !$0.completed }
        let today = Calendar.current.startOfDay(for: now)
        if incomplete.isEmpty { return (.green, 0) }
        if incomplete.contains(where: { $0.startsAt < today }) { return (.red, incomplete.count) }
        if incomplete.contains(where: { $0.startsAt <= now.addingTimeInterval(3_600) }) { return (.amber, incomplete.count) }
        return (.green, incomplete.count)
    }

    private static var snapshotURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: suite)?
            .appendingPathComponent("attendance-widget-v1.bin", isDirectory: false)
    }

    private static var accessGroup: String {
        Bundle.main.object(forInfoDictionaryKey: "SharedKeychainAccessGroup") as? String ?? ""
    }

    private static var keyQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }

    private static func loadOrCreateKey(create: Bool) throws -> SymmetricKey {
        var query = keyQuery
        if !accessGroup.isEmpty { query[kSecAttrAccessGroup as String] = accessGroup }
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecSuccess, let data = result as? Data { return SymmetricKey(data: data) }
        guard status == errSecItemNotFound, create else { throw NSError(domain: NSOSStatusErrorDomain, code: Int(status)) }

        let generated = SymmetricKey(size: .bits256)
        let data = generated.withUnsafeBytes { Data($0) }
        var add = keyQuery
        if !accessGroup.isEmpty { add[kSecAttrAccessGroup as String] = accessGroup }
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let added = SecItemAdd(add as CFDictionary, nil)
        guard added == errSecSuccess else { throw NSError(domain: NSOSStatusErrorDomain, code: Int(added)) }
        return generated
    }
}

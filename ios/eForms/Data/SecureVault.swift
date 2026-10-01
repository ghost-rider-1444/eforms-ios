import CryptoKit
import Foundation
import Security

enum VaultError: LocalizedError {
    case keychain(OSStatus)
    case malformedState

    var errorDescription: String? {
        switch self {
        case .keychain(let status): return "The secure device key is unavailable (\(status))."
        case .malformedState: return "The encrypted offline data is invalid."
        }
    }
}

final class SecureVault {
    static let shared = SecureVault()

    private let service = "app.offlineform.companion.ios.vault-key"
    private let account = "offline-vault-v1"
    private let fileManager = FileManager.default

    private var vaultURL: URL {
        let root = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return root.appendingPathComponent("eforms-offline-vault.bin", isDirectory: false)
    }

    func load() throws -> JSONObject? {
        guard fileManager.fileExists(atPath: vaultURL.path) else { return nil }
        let sealed = try AES.GCM.SealedBox(combined: Data(contentsOf: vaultURL))
        let clear = try AES.GCM.open(sealed, using: loadOrCreateKey())
        guard let object = try JSONSerialization.jsonObject(with: clear) as? JSONObject else {
            throw VaultError.malformedState
        }
        return object
    }

    func save(_ state: JSONObject) throws {
        let clear = try JSONSerialization.data(withJSONObject: state)
        let sealed = try AES.GCM.seal(clear, using: loadOrCreateKey())
        guard let combined = sealed.combined else { throw VaultError.malformedState }
        let folder = vaultURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        let temporary = folder.appendingPathComponent(".eforms-vault-\(UUID().uuidString).tmp")
        try combined.write(to: temporary, options: [.atomic, .completeFileProtectionUnlessOpen])
        if fileManager.fileExists(atPath: vaultURL.path) {
            _ = try fileManager.replaceItemAt(vaultURL, withItemAt: temporary)
        } else {
            try fileManager.moveItem(at: temporary, to: vaultURL)
        }
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var url = vaultURL
        try? url.setResourceValues(values)
    }

    func clear() throws {
        try? fileManager.removeItem(at: vaultURL)
        #if DEBUG
        if usesEphemeralTestKey { return }
        #endif
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let status = SecItemDelete(query as CFDictionary)
        if status != errSecSuccess && status != errSecItemNotFound {
            throw VaultError.keychain(status)
        }
    }

    #if DEBUG
    func rawVaultDataForTests() -> Data? { try? Data(contentsOf: vaultURL) }
    #endif

    private func loadOrCreateKey() throws -> SymmetricKey {
        #if DEBUG
        if usesEphemeralTestKey {
            // Unsigned simulator test hosts cannot use Keychain entitlements. Keep this
            // deterministic key strictly inside DEBUG test processes so persistence,
            // encryption-at-rest and relaunch behaviour can still be exercised in CI.
            return SymmetricKey(data: Data(repeating: 0xA5, count: 32))
        }
        #endif
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecSuccess, let data = result as? Data {
            return SymmetricKey(data: data)
        }
        if status != errSecItemNotFound { throw VaultError.keychain(status) }

        let generated = SymmetricKey(size: .bits256)
        let data = generated.withUnsafeBytes { Data($0) }
        let add: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        let addStatus = SecItemAdd(add as CFDictionary, nil)
        guard addStatus == errSecSuccess else { throw VaultError.keychain(addStatus) }
        return SymmetricKey(data: data)
    }

    #if DEBUG
    private var usesEphemeralTestKey: Bool {
        ProcessInfo.processInfo.arguments.contains("--ui-testing") ||
            ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }
    #endif
}

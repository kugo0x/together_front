import Foundation
import Security

/// Small key → data store for secrets. Tokens live here, never in UserDefaults.
protocol KeychainStore: Sendable {
    func data(for key: String) throws -> Data?
    func set(_ data: Data, for key: String) throws
    func remove(_ key: String) throws
}

struct KeychainError: Error, Equatable {
    let status: OSStatus
}

/// The iOS Keychain (generic passwords, this device only, readable after first unlock).
struct SystemKeychain: KeychainStore {
    var service = "app.smart-note.together.session"

    private func query(_ key: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
    }

    func data(for key: String) throws -> Data? {
        var q = query(key)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(q as CFDictionary, &result)
        switch status {
        case errSecSuccess: return result as? Data
        case errSecItemNotFound: return nil
        default: throw KeychainError(status: status)
        }
    }

    func set(_ data: Data, for key: String) throws {
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        var status = SecItemUpdate(query(key) as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            status = SecItemAdd(query(key).merging(attributes) { $1 } as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw KeychainError(status: status) }
    }

    func remove(_ key: String) throws {
        let status = SecItemDelete(query(key) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw KeychainError(status: status) }
    }
}

/// For tests, previews and UI-test launches: same behaviour, nothing written to the device.
final class InMemoryKeychain: KeychainStore, @unchecked Sendable {
    private var items: [String: Data] = [:]
    private let lock = NSLock()

    init(_ items: [String: Data] = [:]) {
        self.items = items
    }

    func data(for key: String) throws -> Data? {
        lock.withLock { items[key] }
    }

    func set(_ data: Data, for key: String) throws {
        lock.withLock { items[key] = data }
    }

    func remove(_ key: String) throws {
        _ = lock.withLock { items.removeValue(forKey: key) }
    }
}

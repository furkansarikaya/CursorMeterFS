import Foundation
import Security

/// Securely stores and retrieves sensitive data in the macOS Keychain.
///
/// Security guarantees:
/// - Uses `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` — data never leaves this device
///   and is inaccessible when the screen is locked.
/// - Nothing is stored in UserDefaults, files, or logs.
/// - Token strings are never printed; debug descriptions show only length.
enum KeychainService {

    // MARK: - Keys
    enum Key: String {
        case sessionToken    = "com.furkansarikaya.CursorMeterFS.sessionToken"
        case userId          = "com.furkansarikaya.CursorMeterFS.userId"
        case detectedPlan    = "com.furkansarikaya.CursorMeterFS.detectedPlan"
        case refreshToken    = "com.furkansarikaya.CursorMeterFS.refreshToken"
        case email           = "com.furkansarikaya.CursorMeterFS.email"
    }

    enum KeychainError: Error, LocalizedError {
        case encodingFailed
        case saveFailed(OSStatus)
        case loadFailed(OSStatus)
        case notFound
        case deleteFailed(OSStatus)

        var errorDescription: String? {
            switch self {
            case .encodingFailed:          return "Failed to encode data for Keychain."
            case .saveFailed(let s):       return "Keychain save failed (OSStatus \(s))."
            case .loadFailed(let s):       return "Keychain load failed (OSStatus \(s))."
            case .notFound:                return "Item not found in Keychain."
            case .deleteFailed(let s):     return "Keychain delete failed (OSStatus \(s))."
            }
        }
    }

    // MARK: - Write

    /// Saves a string value to the Keychain.  Overwrites any existing value for `key`.
    static func save(_ value: String, for key: Key) throws {
        guard let data = value.data(using: .utf8) else { throw KeychainError.encodingFailed }

        // Delete any existing entry first to avoid `errSecDuplicateItem`
        let deleteQuery: [CFString: Any] = [
            kSecClass:           kSecClassGenericPassword,
            kSecAttrService:     key.rawValue as CFString,
            kSecAttrAccount:     Bundle.main.bundleIdentifier ?? "CursorMeterFS" as CFString,
        ]
        SecItemDelete(deleteQuery as CFDictionary)

        let addQuery: [CFString: Any] = [
            kSecClass:                      kSecClassGenericPassword,
            kSecAttrService:                key.rawValue as CFString,
            kSecAttrAccount:                Bundle.main.bundleIdentifier ?? "CursorMeterFS" as CFString,
            kSecValueData:                  data,
            kSecAttrAccessible:             kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            kSecAttrSynchronizable:         kCFBooleanFalse!,  // never iCloud sync
        ]

        let status = SecItemAdd(addQuery as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeychainError.saveFailed(status) }
    }

    // MARK: - Read

    /// Loads a string value from the Keychain. Throws `.notFound` if the key doesn't exist.
    static func load(key: Key) throws -> String {
        let query: [CFString: Any] = [
            kSecClass:               kSecClassGenericPassword,
            kSecAttrService:         key.rawValue as CFString,
            kSecAttrAccount:         Bundle.main.bundleIdentifier ?? "CursorMeterFS" as CFString,
            kSecReturnData:          kCFBooleanTrue!,
            kSecMatchLimit:          kSecMatchLimitOne,
            kSecAttrSynchronizable:  kCFBooleanFalse!,
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        switch status {
        case errSecSuccess:
            guard let data = result as? Data,
                  let string = String(data: data, encoding: .utf8) else {
                throw KeychainError.loadFailed(errSecDecode)
            }
            return string
        case errSecItemNotFound:
            throw KeychainError.notFound
        default:
            throw KeychainError.loadFailed(status)
        }
    }

    /// Returns nil instead of throwing `.notFound` — convenience for optional loads.
    static func loadOptional(key: Key) -> String? {
        try? load(key: key)
    }

    // MARK: - Delete

    /// Removes a key from the Keychain. Silently succeeds if the key was not present.
    static func delete(key: Key) throws {
        let query: [CFString: Any] = [
            kSecClass:       kSecClassGenericPassword,
            kSecAttrService: key.rawValue as CFString,
            kSecAttrAccount: Bundle.main.bundleIdentifier ?? "CursorMeterFS" as CFString,
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.deleteFailed(status)
        }
    }

    /// Clears all CursorMeter entries from the Keychain (used on "Sign out").
    static func deleteAll() {
        Key.allCases.forEach { key in
            try? delete(key: key)
        }
    }
}

extension KeychainService.Key: CaseIterable {}

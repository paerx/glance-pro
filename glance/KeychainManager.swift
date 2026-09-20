//
//  KeychainManager.swift
//  glance
//
//  Thin, password-agnostic wrapper around Keychain Services — save/read/delete/exists by account, plus a Touch-ID access control helper.
//

import Foundation
import Security
import LocalAuthentication

enum KeychainError: LocalizedError {
    case itemNotFound
    case unexpectedData
    case accessControlFailed(String)
    case authenticationFailed
    case osStatus(OSStatus)

    var errorDescription: String? {
        switch self {
        case .itemNotFound:
            return "Keychain item not found."
        case .unexpectedData:
            return "Keychain item had an unexpected format."
        case .accessControlFailed(let msg):
            return "Couldn't create Keychain access control: \(msg)"
        case .authenticationFailed:
            return "Authentication was cancelled or failed."
        case .osStatus(let status):
            let message = SecCopyErrorMessageString(status, nil) as String? ?? "OSStatus \(status)"
            return "Keychain error: \(message)"
        }
    }
}

enum KeychainManager {
    nonisolated static let service = "com.jonathan.glance"

    /// Attributes-only existence check — never prompts, even for access-controlled items.
    nonisolated static func exists(account: String) -> Bool {
        // UI callers remain conservative on access failures. Security decisions
        // use contains(), which distinguishes "absent" from a query error.
        (try? contains(account: account)) ?? true
    }

    /// Use the same backend for insertion and lookup. Access-control items live
    /// in the data-protection keychain; legacy builds also used the file keychain.
    nonisolated private static func query(account: String, protected: Bool) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account,
         kSecUseDataProtectionKeychain as String: protected]
    }

    nonisolated private static func backend(account: String) throws -> Bool? {
        for protected in [true, false] {
            let context = LAContext()
            context.interactionNotAllowed = true
            var request = query(account: account, protected: protected)
            request[kSecMatchLimit as String] = kSecMatchLimitOne
            request[kSecReturnAttributes as String] = true
            request[kSecUseAuthenticationContext as String] = context
            let status = SecItemCopyMatching(request as CFDictionary, nil)
            switch status {
            case errSecSuccess, errSecInteractionNotAllowed: return protected
            case errSecItemNotFound: continue
            default: throw KeychainError.osStatus(status)
            }
        }
        return nil
    }

    nonisolated static func contains(account: String) throws -> Bool {
        try backend(account: account) != nil
    }

    nonisolated static func read(account: String, context: LAContext? = nil) throws -> Data {
        guard let protected = try backend(account: account) else { throw KeychainError.itemNotFound }
        var request = query(account: account, protected: protected)
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        if let context { request[kSecUseAuthenticationContext as String] = context }
        var item: CFTypeRef?
        let status = SecItemCopyMatching(request as CFDictionary, &item)
        switch status {
        case errSecSuccess:
            guard let data = item as? Data else { throw KeychainError.unexpectedData }
            return data
        case errSecItemNotFound: throw KeychainError.itemNotFound
        case errSecUserCanceled, errSecAuthFailed: throw KeychainError.authenticationFailed
        default: throw KeychainError.osStatus(status)
        }
    }

    nonisolated static func save(account: String, data: Data, accessControl: SecAccessControl? = nil) throws {
        guard let protected = try backend(account: account) else {
            try create(account: account, data: data, accessControl: accessControl)
            return
        }
        let status = SecItemUpdate(query(account: account, protected: protected) as CFDictionary,
                                   [kSecValueData as String: data] as CFDictionary)
        guard status == errSecSuccess else { throw KeychainError.osStatus(status) }
    }

    /// Insert-only; never replace a key after a cancelled authentication.
    nonisolated static func create(account: String, data: Data, accessControl: SecAccessControl? = nil) throws {
        var request = query(account: account, protected: true)
        request[kSecValueData as String] = data
        if let accessControl { request[kSecAttrAccessControl as String] = accessControl }
        else { request[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly }
        let status = SecItemAdd(request as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeychainError.osStatus(status) }
    }

    nonisolated static func delete(account: String) throws {
        guard let protected = try backend(account: account) else { return }
        let status = SecItemDelete(query(account: account, protected: protected) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw KeychainError.osStatus(status) }
    }

    /// `.userPresence` requires Touch ID or device password, with no separate no-hardware handling needed.
    nonisolated static func makeUserPresenceAccessControl() throws -> SecAccessControl {
        var accessError: Unmanaged<CFError>?
        guard let access = SecAccessControlCreateWithFlags(
            kCFAllocatorDefault,
            kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            .userPresence,
            &accessError
        ) else {
            let msg = (accessError?.takeRetainedValue() as Error?)?.localizedDescription ?? "unknown"
            throw KeychainError.accessControlFailed(msg)
        }
        return access
    }
}

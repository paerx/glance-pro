// Compile with the REAL SecureCredentialManager.swift. The fake backends below
// never access the user's Keychain, files or preferences, and never prompt.
import Foundation
import CryptoKit
import LocalAuthentication

nonisolated enum KeychainError: Error { case unexpectedData, denied, duplicate, queryFailure }
nonisolated enum CredentialVault {
    static var identifier: String?
    static var activations = 0
    static func account(_ base: String, vault: String? = identifier) -> String { vault.map { "\(base).\($0)" } ?? base }
    static func activate(_ value: String) throws { identifier = value; activations += 1 }
}
nonisolated enum SecureFaceStore {
    static var stored = Set<String>()
    static var exists: Bool { stored.contains(CredentialVault.identifier ?? "legacy") }
}
nonisolated enum KeychainManager {
    static var items: [String: Data] = [:]
    static var failRead = false
    static var failQuery = false
    static var creates = 0
    static var reads = 0
    static func contains(account: String) throws -> Bool {
        if failQuery { throw KeychainError.queryFailure }
        return items[account] != nil
    }
    static func exists(account: String) -> Bool { (try? contains(account: account)) ?? true }
    static func read(account: String, context: LAContext? = nil) throws -> Data {
        reads += 1
        if failRead { throw KeychainError.denied }
        guard let data = items[account] else { throw KeychainError.unexpectedData }
        return data
    }
    static func create(account: String, data: Data, accessControl: Bool? = nil) throws {
        guard items[account] == nil else { throw KeychainError.duplicate }
        creates += 1
        items[account] = data
    }
    static func save(account: String, data: Data) throws { items[account] = data }
    static func delete(account: String) throws { items.removeValue(forKey: account) }
    static func makeUserPresenceAccessControl() throws -> Bool { true }
}

@main struct CredentialSelfTest {
    static var checks = 0
    static func check(_ value: @autoclosure () -> Bool, _ label: String) {
        precondition(value(), label); checks += 1
    }
    static func reset() {
        SecureCredentialManager.lockSession()
        CredentialVault.identifier = nil; CredentialVault.activations = 0
        KeychainManager.items = [:]; KeychainManager.creates = 0; KeychainManager.reads = 0
        KeychainManager.failRead = false; KeychainManager.failQuery = false
        SecureFaceStore.stored = []
    }
    static func expectError(_ body: () throws -> Void) {
        do { try body(); preconditionFailure("Expected failure") } catch { checks += 1 }
    }
    static func main() throws {
        reset()
        let oldCipher = Data("old encrypted fixture".utf8)
        KeychainManager.items["encryptedPassword"] = oldCipher
        SecureFaceStore.stored.insert("legacy")
        do { try SecureCredentialManager.unlockSession(reason: "test"); preconditionFailure() }
        catch { check((error as? SecureCredentialError) == .sessionKeyUnavailable, "orphan is detected") }
        check(KeychainManager.creates == 0, "never mint a replacement over orphan data")
        check(KeychainManager.items["encryptedPassword"] == oldCipher, "old password unchanged")

        KeychainManager.failRead = true
        expectError { try SecureCredentialManager.startNewVaultPreservingPreviousData() }
        check(CredentialVault.identifier == nil, "cancelled gate leaves old vault active")
        check(!SecureCredentialManager.isSessionUnlocked, "cancelled gate never caches a key")
        check(SecureFaceStore.exists, "old face file still selected")

        KeychainManager.failRead = false
        try SecureCredentialManager.startNewVaultPreservingPreviousData()
        check(CredentialVault.activations == 1, "activate only after successful gated read")
        check(SecureCredentialManager.isSessionUnlocked, "recovered session usable")
        check(SecureFaceStore.stored.contains("legacy"), "old face file retained")
        check(KeychainManager.items["encryptedPassword"] == oldCipher, "old password retained")
        check(!SecureFaceStore.exists, "new vault starts with a separate face path")
        let freshPassword = Data("test-password".utf8)
        try SecureCredentialManager.savePassword(freshPassword)
        let readBack = try SecureCredentialManager.readPassword()
        check(readBack == freshPassword, "new vault encrypt/decrypt round trip")
        check(KeychainManager.items["encryptedPassword"] == oldCipher, "new save doesn't overwrite old credential")
        SecureCredentialManager.lockSession()
        try SecureCredentialManager.unlockSession(reason: "test")
        let reread = try SecureCredentialManager.readPassword()
        check(reread == freshPassword, "new vault can be reopened")

        reset()
        KeychainManager.failQuery = true
        expectError { try SecureCredentialManager.unlockSession(reason: "test") }
        check(KeychainManager.creates == 0, "query errors are not treated as missing keys")

        reset()
        KeychainManager.items["sessionKey"] = Data(repeating: 7, count: 32)
        KeychainManager.failRead = true
        expectError { try SecureCredentialManager.unlockSession(reason: "test") }
        check(KeychainManager.creates == 0 && !SecureCredentialManager.isSessionUnlocked, "auth failure cannot replace a key")
        KeychainManager.failRead = false
        expectError { try SecureCredentialManager.startNewVaultPreservingPreviousData() }
        check(CredentialVault.identifier == nil, "recovery refuses an existing key")
        KeychainManager.items["sessionKey"] = Data(repeating: 7, count: 1)
        expectError { try SecureCredentialManager.unlockSession(reason: "test") }
        check(!SecureCredentialManager.isSessionUnlocked, "invalid key length rejected")

        reset()
        let group = DispatchGroup()
        for _ in 0..<8 {
            group.enter()
            DispatchQueue.global().async {
                defer { group.leave() }
                try! SecureCredentialManager.unlockSession(reason: "test")
            }
        }
        group.wait()
        check(KeychainManager.creates == 1 && KeychainManager.reads == 1, "concurrent callers share one authenticated key")
        SecureFaceStore.stored.insert("legacy")
        expectError { try SecureCredentialManager.deletePassword() }
        check(KeychainManager.items["sessionKey"] != nil, "failed face deletion preserves decryption key")
        reset()
        print("PASS: \(checks) credential checks; no real Keychain or user data accessed")
    }
}

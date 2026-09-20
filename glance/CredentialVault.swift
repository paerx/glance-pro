import Foundation

/// Recovery selects a new namespace only after its user-presence-gated key has
/// been read successfully. The old Keychain items and encrypted face file stay
/// byte-for-byte intact; losing access to a key must never delete its ciphertext.
nonisolated enum CredentialVault {
    private static let preference = "Glance.activeCredentialVault"

    private static var manifestURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("glance", isDirectory: true)
            .appendingPathComponent("active-vault.txt")
    }

    static var identifier: String? {
        // Persist alongside encrypted faces, so rebuilding with a different
        // preferences domain cannot accidentally select the legacy vault.
        if let raw = try? String(contentsOf: manifestURL, encoding: .utf8), UUID(uuidString: raw) != nil { return raw }
        guard let raw = UserDefaults.standard.string(forKey: preference), UUID(uuidString: raw) != nil else { return nil }
        return raw
    }

    static func account(_ base: String, vault: String? = identifier) -> String {
        vault.map { "\(base).\($0)" } ?? base
    }

    static var faceFilename: String {
        identifier.map { "face-identities-\($0).enc" } ?? "face-identities.enc"
    }

    static func activate(_ identifier: String) throws {
        precondition(UUID(uuidString: identifier) != nil)
        try FileManager.default.createDirectory(at: manifestURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(identifier.utf8).write(to: manifestURL, options: .atomic)
        UserDefaults.standard.set(identifier, forKey: preference)
    }
}

// Compile with glance/KeychainManager.swift. These local Security entry points
// shadow the imported C functions; this executable never accesses a keychain.
import Foundation
import Security
import LocalAuthentication

var items: [Bool: Data] = [:]
var probes: [Bool] = []
var readError: OSStatus?
var probeError: OSStatus?
func SecItemCopyMatching(_ query: CFDictionary, _ result: UnsafeMutablePointer<CFTypeRef?>?) -> OSStatus {
    let q = query as NSDictionary
    let backend = q[kSecUseDataProtectionKeychain] as! Bool
    probes.append(backend)
    if q[kSecReturnData] as? Bool == true {
        if let readError { return readError }
        guard let data = items[backend] else { return errSecItemNotFound }
        result?.pointee = data as CFData
        return errSecSuccess
    }
    if let probeError { return probeError }
    return items[backend] == nil ? errSecItemNotFound : errSecSuccess
}
func SecItemAdd(_ query: CFDictionary, _ result: UnsafeMutablePointer<CFTypeRef?>?) -> OSStatus {
    let q = query as NSDictionary
    let backend = q[kSecUseDataProtectionKeychain] as! Bool
    guard items[backend] == nil else { return errSecDuplicateItem }
    items[backend] = q[kSecValueData] as? Data
    return errSecSuccess
}
func SecItemUpdate(_ query: CFDictionary, _ changes: CFDictionary) -> OSStatus {
    let backend = (query as NSDictionary)[kSecUseDataProtectionKeychain] as! Bool
    guard items[backend] != nil else { return errSecItemNotFound }
    items[backend] = (changes as NSDictionary)[kSecValueData] as? Data
    return errSecSuccess
}
func SecItemDelete(_ query: CFDictionary) -> OSStatus {
    let backend = (query as NSDictionary)[kSecUseDataProtectionKeychain] as! Bool
    items[backend] = nil
    return errSecSuccess
}
@main struct BackendSelfTest {
    static var checks = 0
    static func check(_ ok: Bool, _ message: String) { precondition(ok, message); checks += 1 }
    static func main() throws {
        check(try !KeychainManager.contains(account: "test"), "absent in both backends")
        check(probes == [true, false], "look in DP then legacy")
        try KeychainManager.create(account: "test", data: Data([1]))
        check(items[true] == Data([1]) && items[false] == nil, "create explicitly in DP")
        check(try KeychainManager.read(account: "test") == Data([1]), "read same backend after insertion")
        items[false] = Data([2])
        check(try KeychainManager.read(account: "test") == Data([1]), "DP wins when both exist")
        readError = errSecUserCanceled
        do { _ = try KeychainManager.read(account: "test"); preconditionFailure("cancel ignored") }
        catch KeychainError.authenticationFailed { checks += 1 }
        check(items[true] == Data([1]) && items[false] == Data([2]), "cancel preserves both keys")
        readError = nil
        try KeychainManager.delete(account: "test")
        check(items[true] == nil && items[false] == Data([2]), "delete only selected backend")
        check(try KeychainManager.read(account: "test") == Data([2]), "legacy readable")
        try KeychainManager.save(account: "test", data: Data([3]))
        check(items[false] == Data([3]) && items[true] == nil, "update legacy in place")
        probeError = errSecMissingEntitlement
        do { _ = try KeychainManager.contains(account: "test"); preconditionFailure("error treated as missing") }
        catch KeychainError.osStatus(let status) { check(status == errSecMissingEntitlement, "access errors fail closed") }
        probeError = errSecInteractionNotAllowed
        check(try KeychainManager.contains(account: "test"), "gated item is present without prompting")
        print("PASS: \(checks) backend checks; Security functions are in-memory doubles")
    }
}

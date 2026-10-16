import Foundation
@testable import RaccoonData
import RaccoonDomain
import Security
import Testing

/// Against the real login keychain, under a service name no one else uses, removed afterwards.
final class KeychainSecretStoreTests {
    let service = "raccoon-test-\(UUID())"
    let token = VariableName("token")!

    deinit {
        for environment in [service, "\(service)/Prod", "\(service)/Dev"] {
            SecItemDelete([kSecClass: kSecClassGenericPassword, kSecAttrService: environment] as CFDictionary)
        }
    }

    @Test func `set, get and delete a secret per Environment and for Globals`() throws {
        let store = KeychainSecretStore(service: service)

        try store.set("prod-1", environment: "Prod", name: token)
        try store.set("global-1", environment: nil, name: token)
        try store.set("prod-2", environment: "Prod", name: token)

        #expect(try store.get(environment: "Prod", name: token) == "prod-2")
        #expect(try store.get(environment: nil, name: token) == "global-1")
        #expect(try store.get(environment: "Dev", name: token) == nil)

        try store.delete(environment: "Prod", name: token)
        try store.delete(environment: "Prod", name: token)
        #expect(try store.get(environment: "Prod", name: token) == nil)
    }

    @Test func `an item that is not UTF-8 reads as absent`() throws {
        let status = SecItemAdd([
            kSecClass: kSecClassGenericPassword, kSecAttrService: "\(service)/Prod", kSecAttrAccount: "token",
            kSecValueData: Data([0xFF, 0xFE, 0xFD]),
        ] as CFDictionary, nil)
        try #require(status == errSecSuccess)

        #expect(try KeychainSecretStore(service: service).get(environment: "Prod", name: token) == nil)
    }

    @Test func `a failed set carries the OSStatus`() {
        // An unsigned test process has no entitlement for the data protection keychain.
        let store = KeychainSecretStore(service: service, usesDataProtectionKeychain: true)

        #expect(throws: SecretError.unavailable(errSecMissingEntitlement)) {
            try store.set("v", environment: "Prod", name: token)
        }
    }
}

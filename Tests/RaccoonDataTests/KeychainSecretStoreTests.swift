import Foundation
@testable import RaccoonData
import RaccoonDomain
import Security
import Testing

/// Against the real login keychain, under fresh WorkspaceIDs, whose items are removed afterwards,
/// pass or fail.
final class KeychainSecretStoreTests {
    let work = WorkspaceID(UUID())
    let side = WorkspaceID(UUID())
    let token = VariableName("token")!

    deinit {
        for id in [work, side] {
            for service in ["Raccoon/\(id.rawValue.uuidString)", "Raccoon/\(id.rawValue.uuidString)/Prod"] {
                SecItemDelete([kSecClass: kSecClassGenericPassword, kSecAttrService: service] as CFDictionary)
            }
        }
    }

    @Test func `set, get and delete a secret per Environment and for Globals`() throws {
        let store = KeychainSecretStore(id: work)

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

    @Test func `two Workspaces keep separate values for the same Environment and Variable`() throws {
        try KeychainSecretStore(id: work).set("work-1", environment: "Prod", name: token)
        try KeychainSecretStore(id: side).set("side-1", environment: "Prod", name: token)

        #expect(try KeychainSecretStore(id: work).get(environment: "Prod", name: token) == "work-1")
        #expect(try KeychainSecretStore(id: side).get(environment: "Prod", name: token) == "side-1")
    }

    @Test func `the service is Raccoon slash the id, then the Environment`() throws {
        try KeychainSecretStore(id: work).set("v", environment: "Prod", name: token)

        let found = SecItemCopyMatching([
            kSecClass: kSecClassGenericPassword, kSecAttrService: "Raccoon/\(work.rawValue.uuidString)/Prod",
            kSecAttrAccount: "token",
        ] as CFDictionary, nil)
        #expect(found == errSecSuccess)
    }

    @Test func `an item that is not UTF-8 reads as absent`() throws {
        let status = SecItemAdd([
            kSecClass: kSecClassGenericPassword, kSecAttrService: "Raccoon/\(work.rawValue.uuidString)/Prod", kSecAttrAccount: "token",
            kSecValueData: Data([0xFF, 0xFE, 0xFD]),
        ] as CFDictionary, nil)
        try #require(status == errSecSuccess)

        #expect(try KeychainSecretStore(id: work).get(environment: "Prod", name: token) == nil)
    }

    @Test func `a failed set carries the OSStatus`() {
        // An unsigned test process has no entitlement for the data protection keychain.
        let store = KeychainSecretStore(id: work, usesDataProtectionKeychain: true)

        #expect(throws: SecretError.unavailable(errSecMissingEntitlement)) {
            try store.set("v", environment: "Prod", name: token)
        }
    }

    @Test func `with no WorkspaceID, get is nil, set and delete throw, and nothing reaches the Keychain`() throws {
        // A name no other item uses, so any item with it would be this store's.
        let name = try #require(VariableName("raccoon-test-\(UUID().uuidString)"))
        let store = NoWorkspaceIDSecretStore()

        #expect(try store.get(environment: nil, name: name) == nil)
        #expect(throws: SecretError.raccoonJSONUnreadable) { try store.set("v", environment: "Prod", name: name) }
        #expect(throws: SecretError.raccoonJSONUnreadable) { try store.delete(environment: nil, name: name) }

        let found = SecItemCopyMatching([kSecClass: kSecClassGenericPassword, kSecAttrAccount: name.rawValue] as CFDictionary, nil)
        #expect(found == errSecItemNotFound)
    }
}

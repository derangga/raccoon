import Foundation
import RaccoonDomain
import Security

/// One Workspace's Secret Variables in the login keychain, one generic password each: service
/// `Raccoon/<WorkspaceID>` for Globals or `Raccoon/<WorkspaceID>/<Environment>`, account the
/// Variable name. A VariableName holds no `/` and an Environment name is a file name, so two keys
/// never collide.
public struct KeychainSecretStore: SecretStore {
    private let service: String
    private let usesDataProtectionKeychain: Bool

    public init(id: WorkspaceID) {
        self.init(id: id, usesDataProtectionKeychain: false)
    }

    /// The data protection keychain needs an entitlement an unsigned build lacks, which is how
    /// tests get a real failure.
    init(id: WorkspaceID, usesDataProtectionKeychain: Bool) {
        service = "Raccoon/\(id.rawValue.uuidString)"
        self.usesDataProtectionKeychain = usesDataProtectionKeychain
    }

    private func query(_ environment: String?, _ name: VariableName) -> [CFString: Any] {
        var query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: environment.map { "\(service)/\($0)" } ?? service,
            kSecAttrAccount: name.rawValue,
        ]
        if usesDataProtectionKeychain { query[kSecUseDataProtectionKeychain] = true }
        return query
    }

    /// A value that is not UTF-8 is absent, so it surfaces as an Undefined Variable.
    public func get(environment: String?, name: VariableName) throws(SecretError) -> String? {
        var search = query(environment, name)
        search[kSecReturnData] = true
        search[kSecMatchLimit] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(search as CFDictionary, &result)
        guard status != errSecItemNotFound else { return nil }
        guard status == errSecSuccess else { throw .unavailable(status) }
        return (result as? Data).flatMap { String(data: $0, encoding: .utf8) }
    }

    public func set(_ value: String, environment: String?, name: VariableName) throws(SecretError) {
        let item = query(environment, name)
        let data = Data(value.utf8)
        var status = SecItemAdd(item.merging([kSecValueData: data]) { $1 } as CFDictionary, nil)
        if status == errSecDuplicateItem {
            status = SecItemUpdate(item as CFDictionary, [kSecValueData: data] as CFDictionary)
        }
        guard status == errSecSuccess else { throw .unavailable(status) }
    }

    public func delete(environment: String?, name: VariableName) throws(SecretError) {
        let status = SecItemDelete(query(environment, name) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw .unavailable(status) }
    }
}

/// A Workspace whose raccoon.json is undecodable or could not be written has no id, so its
/// secrets have no Keychain service. Never touches the Keychain: every secret is undefined.
public struct NoWorkspaceIDSecretStore: SecretStore {
    public init() {}

    public func get(environment: String?, name: VariableName) throws(SecretError) -> String? { nil }

    public func set(_ value: String, environment: String?, name: VariableName) throws(SecretError) {
        throw .raccoonJSONUnreadable
    }

    public func delete(environment: String?, name: VariableName) throws(SecretError) {
        throw .raccoonJSONUnreadable
    }
}

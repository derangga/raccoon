import Foundation

/// Where in a Request a Credential is typed.
public enum CredentialPlace: Equatable, Sendable {
    case header(String)
    case query(String)
    case bearerToken
    case basicPassword
}

/// One literal Credential: the Request's name and where. No value, so no sheet can print one.
public struct CredentialFinding: Equatable, Sendable {
    public var request: String
    public var place: CredentialPlace

    public init(request: String, place: CredentialPlace) {
        self.request = request
        self.place = place
    }
}

/// Postman Export's warning: the literal Credentials in the Requests the exporter writes. Pure.
public enum CredentialScan {
    /// Per Request, in order: Headers rows, Params rows, then the Auth field. Disabled Rows count,
    /// because the file holds them. A Cookie header is not found because `Cookie` is not a
    /// credential name. Request Cookies, Body fields and the URL are not scanned.
    public static func find(_ requests: [Request]) -> [CredentialFinding] {
        requests.flatMap { request in
            let definition = request.definition
            var places = definition.headers.filter(isCredential).map { CredentialPlace.header($0.name) }
                + definition.params.filter(isCredential).map { CredentialPlace.query($0.name) }
            switch definition.auth {
            case .none: break
            case .bearer(let token): if isTyped(token) { places.append(.bearerToken) }
            case .basic(_, let password): if isTyped(password) { places.append(.basicPassword) }
            }
            return places.map { CredentialFinding(request: request.name, place: $0) }
        }
    }

    private static func isCredential(_ row: Row) -> Bool {
        isCredentialName(row.name) && isLiteral(row.value)
    }

    /// Not a `{{name}}` reference. `{{$name}}` and an empty value are text, so they count.
    private static func isLiteral(_ value: String) -> Bool {
        VariableTokens.ranges(value).isEmpty
    }

    /// An Auth field with nothing in it, or only whitespace, holds no Credential.
    private static func isTyped(_ value: String) -> Bool {
        !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && isLiteral(value)
    }

    private static let exactNames: Set<String> = ["authorization", "proxy-authorization", "key"]
    private static let nameParts = ["token", "secret", "password", "passwd", "apikey", "api-key", "api_key"]

    private static func isCredentialName(_ name: String) -> Bool {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return exactNames.contains(name) || nameParts.contains { name.contains($0) }
    }
}

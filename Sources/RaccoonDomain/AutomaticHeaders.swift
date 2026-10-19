import Foundation

/// A header that is sent although no row sets it.
public struct AutomaticHeader: Equatable, Sendable {
    public var name: String
    /// nil when it is only known at send: Content-Length.
    public var value: String?

    public init(name: String, value: String?) {
        self.name = name
        self.value = value
    }
}

/// The headers URLSession adds that no row sets (environment-facts.md). None can be removed, only
/// replaced by a row of the same name, so the Headers table shows them instead of hiding them.
public enum AutomaticHeaders {
    /// Set by the transport in place of URLSession's own, which carries build numbers.
    public static let userAgent = "Raccoon/0.1"
    /// Set by the transport in place of the system's list, which cannot be read ahead.
    public static let acceptLanguage = "*"

    public static func rows(for request: ResolvedRequest) -> [AutomaticHeader] {
        let definition = request.definition
        let host = request.url.host() ?? ""
        let secure = request.url.scheme?.lowercased() == "https"
        var rows = [
            AutomaticHeader(name: "Host", value: request.url.port.map { "\(host):\($0)" } ?? host),
            AutomaticHeader(name: "Accept", value: "*/*"),
            AutomaticHeader(name: "Accept-Language", value: acceptLanguage),
            AutomaticHeader(name: "Accept-Encoding", value: secure ? "gzip, deflate, br" : "gzip, deflate"),
            AutomaticHeader(name: "Connection", value: "keep-alive"),
            AutomaticHeader(name: "User-Agent", value: userAgent),
        ]
        switch definition.body {
        case .none: break
        case .multipart:
            rows += [AutomaticHeader(name: "Content-Type", value: "multipart/form-data"), AutomaticHeader(name: "Content-Length", value: nil)]
        case .raw, .formURLEncoded:
            // Only POST gets the form Content-Type; DELETE, PUT and PATCH send the body without one.
            if definition.method.uppercased() == "POST" {
                rows.append(AutomaticHeader(name: "Content-Type", value: "application/x-www-form-urlencoded"))
            }
            rows.append(AutomaticHeader(name: "Content-Length", value: nil))
        }
        // The resolver dropped Disabled Rows, so every row left is sent.
        return rows.filter { row in !definition.headers.contains { $0.name.caseInsensitiveCompare(row.name) == .orderedSame } }
    }
}

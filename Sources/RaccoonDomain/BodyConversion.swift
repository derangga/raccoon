import Foundation

/// What the Body Type pop-up picks.
public enum BodyType: Equatable, Sendable {
    case none
    case raw(RawKind)
    case formURLEncoded
    case multipart
}

extension Body {
    public var type: BodyType {
        switch self {
        case .none: .none
        case .raw(let kind, _): .raw(kind)
        case .formURLEncoded: .formURLEncoded
        case .multipart: .multipart
        }
    }
}

public enum BodyConversion {
    /// raw → raw keeps the text, form ↔ multipart keeps the rows (text parts only), anything →
    /// none keeps nothing, and every other pair starts empty.
    public static func convert(_ body: Body, to type: BodyType) -> Body {
        switch (body, type) {
        case (_, .none): .none
        case (.raw(_, let text), .raw(let kind)): .raw(kind, text)
        case (_, .raw(let kind)): .raw(kind, "")
        case (.formURLEncoded, .formURLEncoded), (.multipart, .multipart): body
        case (.multipart(let parts), .formURLEncoded):
            .formURLEncoded(parts.compactMap { part in
                guard case .text(let value) = part.content else { return nil }
                return Row(name: part.name, value: value, isEnabled: part.isEnabled)
            })
        case (_, .formURLEncoded): .formURLEncoded([])
        case (.formURLEncoded(let rows), .multipart):
            .multipart(rows.map { Part(name: $0.name, isEnabled: $0.isEnabled, content: .text($0.value)) })
        case (_, .multipart): .multipart([])
        }
    }
}

public enum Headers {
    /// Content-Type as a visible row. It is written only when the user has none, or when the row
    /// there is the one this rule wrote for the old Body Type: enabled, with that exact value.
    /// Multipart's row has no boundary; the transport appends it.
    public static func contentType(_ headers: [Row], from old: BodyType, to new: BodyType) -> [Row] {
        var headers = headers
        guard let index = headers.firstIndex(where: { $0.name.caseInsensitiveCompare("Content-Type") == .orderedSame }) else {
            if let value = value(for: new) { headers.append(Row(name: "Content-Type", value: value)) }
            return headers
        }
        guard headers[index].isEnabled, headers[index].value == value(for: old) else { return headers }
        if let value = value(for: new) { headers[index].value = value } else { headers.remove(at: index) }
        return headers
    }

    private static func value(for type: BodyType) -> String? {
        switch type {
        case .none: nil
        case .raw(.json): "application/json"
        case .raw(.text): "text/plain"
        case .raw(.xml): "application/xml"
        case .formURLEncoded: "application/x-www-form-urlencoded"
        case .multipart: "multipart/form-data"
        }
    }
}

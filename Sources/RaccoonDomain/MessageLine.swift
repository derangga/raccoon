/// The one line under the URL bar (design-system.md §6 URL bar).
public enum MessageLine: Equatable, Sendable {
    /// Curl Import errors and "Not sent." with the undefined names.
    case error(String)
    /// The Ignored note, dismissable.
    case note(String)

    /// A note goes away on the next URL edit; an error stays until the next send or paste.
    public var afterURLEdit: MessageLine? {
        if case .note = self { return nil }
        return self
    }

    public var afterSendOrPaste: MessageLine? {
        if case .error = self { return nil }
        return self
    }

    /// Board 04: "Not sent. a and b are not defined in Staging or in Globals." Every name, in
    /// the order the request uses them.
    public static func undefined(_ names: [VariableName], in environment: String?) -> MessageLine {
        let where_ = environment.map { "\($0) or in Globals" } ?? "Globals"
        return .error("Not sent. \(VariableName.phrase(names)) \(names.count == 1 ? "is" : "are") not defined in \(where_).")
    }
}

extension VariableName {
    /// "a", "a and b", "a, b and c".
    public static func phrase(_ names: [VariableName]) -> String {
        let raw = names.map(\.rawValue)
        guard raw.count > 1 else { return raw.first ?? "" }
        return raw.dropLast().joined(separator: ", ") + " and " + raw.last!
    }
}

extension ColorToken {
    /// Methods are free text (shapes.md): anything but the seven listed is `methodOther`.
    public static func method(_ method: String) -> ColorToken {
        switch method {
        case "GET": .methodGet
        case "POST": .methodPost
        case "PUT": .methodPut
        case "PATCH": .methodPatch
        case "DELETE": .methodDelete
        case "HEAD": .methodHead
        case "OPTIONS": .methodOptions
        default: .methodOther
        }
    }
}

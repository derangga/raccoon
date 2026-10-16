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

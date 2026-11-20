import Foundation

/// What the Mock Server sheet's Port field says: nothing, a usable port, or text that is neither.
public enum MockPort: Equatable, Sendable {
    /// The field is empty: the system picks a free port.
    case automatic
    case port(UInt16)
    case invalid

    /// Empty is `.automatic`, a whole number from 1024 to 65535 is `.port`, anything else is
    /// `.invalid`. Spaces and newlines around the text are trimmed. Pure and total.
    public static func parse(_ text: String) -> MockPort {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return .automatic }
        // Digits only: UInt16(_:) would take a leading "+", and it returns nil, never traps, on overflow.
        guard trimmed.utf8.allSatisfy({ (UInt8(ascii: "0")...UInt8(ascii: "9")).contains($0) }),
              let value = UInt16(trimmed), value >= 1024 else { return .invalid }
        return .port(value)
    }
}

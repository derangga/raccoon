import Foundation

/// Typing `{{` in a field that takes Variables offers the names in scope (design-system §6
/// Variable suggestions). Offsets are UTF-16, as text storage counts.
public enum VariableCompletion {
    public struct Query: Equatable, Sendable {
        /// The name characters typed after `{{`, ending at the caret.
        public var range: NSRange
        public var prefix: String
    }

    public struct Insertion: Equatable, Sendable {
        public var range: NSRange
        public var text: String
        /// Where the caret goes: after the `}}`.
        public var caret: Int
    }

    /// The `{{` and name characters that end at `caret`, or nil when the caret is not right after one.
    public static func query(in text: String, caret: Int) -> Query? {
        let units = Array(text.utf16)
        guard caret <= units.count else { return nil }
        var start = caret
        while start > 0, isNameUnit(units[start - 1]) { start -= 1 }
        guard start >= 2, units[start - 1] == 0x7B, units[start - 2] == 0x7B else { return nil }
        let range = NSRange(location: start, length: caret - start)
        return Query(range: range, prefix: (text as NSString).substring(with: range))
    }

    /// `name}}` over the typed name, any name characters after the caret, and a `}}` already there.
    public static func insertion(of name: VariableName, for query: Query, in text: String) -> Insertion {
        let units = Array(text.utf16)
        var end = NSMaxRange(query.range)
        while end < units.count, isNameUnit(units[end]) { end += 1 }
        if end + 1 < units.count, units[end] == 0x7D, units[end + 1] == 0x7D { end += 2 }
        let replacement = name.rawValue + "}}"
        return Insertion(
            range: NSRange(location: query.range.location, length: end - query.range.location),
            text: replacement,
            caret: query.range.location + replacement.utf16.count
        )
    }

    /// ASCII letters and digits, `_`, `-` and `.`: what a VariableName holds.
    private static func isNameUnit(_ unit: UInt16) -> Bool {
        switch unit {
        case 0x30...0x39, 0x41...0x5A, 0x61...0x7A, 0x5F, 0x2D, 0x2E: true
        default: false
        }
    }
}

/// One row of the suggestion list. Never a value: a secret's is in the Keychain, and a plain one
/// is not what the list is for.
public struct VariableSuggestion: Equatable, Sendable {
    public var name: VariableName
    /// The Environment's name, or "Globals".
    public var source: String
    public var isSecret: Bool

    public init(name: VariableName, source: String, isSecret: Bool) {
        self.name = name
        self.source = source
        self.isSecret = isSecret
    }
}

import Foundation

/// One `{{name}}` in a field. The range covers the braces, in UTF-16 units as text storage takes it.
public struct VariableToken: Equatable, Sendable {
    public var range: NSRange
    public var name: VariableName

    public init(range: NSRange, name: VariableName) {
        self.range = range
        self.name = name
    }
}

/// Where the Variables are in a text: what resolution substitutes and what the editors colour.
public enum VariableTokens {
    /// One linear pass, so it runs on every keystroke with no debounce (behavior.md §7).
    /// `{{ name }}` is `{{name}}`; braces around anything that is not a VariableName are text.
    public static func ranges(_ text: String) -> [VariableToken] {
        let u = Array(text.utf16)
        let open: UInt16 = 0x7B, close: UInt16 = 0x7D, space: UInt16 = 0x20
        var tokens: [VariableToken] = []
        var i = 0
        while i + 1 < u.count {
            guard u[i] == open, u[i + 1] == open else { i += 1; continue }
            var j = i + 2
            while j < u.count, u[j] == space || isNameUnit(u[j]) { j += 1 }
            if j + 1 < u.count, u[j] == close, u[j + 1] == close {
                var (start, end) = (i + 2, j)
                while start < end, u[start] == space { start += 1 }
                while end > start, u[end - 1] == space { end -= 1 }
                // Every unit is a name unit or a space already, so a name is non-empty with no space.
                if start < end, !u[start..<end].contains(space) {
                    let name = VariableName(validated: String(decoding: u[start..<end], as: UTF16.self))
                    tokens.append(VariableToken(range: NSRange(location: i, length: j + 2 - i), name: name))
                    i = j + 2
                    continue
                }
            }
            // Nothing between i + 2 and j is a brace, so no token starts there. When j stopped
            // right away it stopped on a `{`, and `{{` may start at i + 1.
            i = j == i + 2 ? i + 1 : j
        }
        return tokens
    }

    /// ASCII letters and digits, `_`, `-` and `.`: what VariableName accepts.
    private static func isNameUnit(_ unit: UInt16) -> Bool {
        switch unit {
        case 0x30...0x39, 0x41...0x5A, 0x61...0x7A, 0x5F, 0x2D, 0x2E: true
        default: false
        }
    }
}

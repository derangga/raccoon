import Foundation

/// One coloured stretch of a body. The range is in UTF-16 units, as text storage takes it.
public struct HighlightRange: Equatable, Sendable {
    public var range: NSRange
    public var token: ColorToken

    public init(range: NSRange, token: ColorToken) {
        self.range = range
        self.token = token
    }
}

/// Syntax ranges for the Response viewer and the raw body editor. It never fails: the editor
/// highlights half-typed text, so whatever is recognised is coloured and the rest is left alone.
/// `{{name}}` is left for the Variable highlight drawn on top.
public enum Highlighter {
    public static func ranges(_ text: String, kind: RawKind) -> [HighlightRange] {
        switch kind {
        case .json: json(Array(text.utf16))
        case .xml: xml(Array(text.utf16))
        case .text: []
        }
    }

    /// Ranges for a GraphQL query, reusing the JSON tokens. A keyword is `jsonBoolean`, `null` is
    /// `jsonNull`, any other name is `jsonKey`, a GraphQL variable (`$id`) is `jsonNull`. A plain string
    /// ends at its line. Text that does not lex is left plain from that point on. A Variable
    /// (`{{name}}`) is left uncovered, bare or inside a string or comment.
    public static func graphql(_ text: String) -> [HighlightRange] {
        let u = Array(text.utf16)
        let variables = VariableTokens.ranges(text).map(\.range)  // in text order, so one cursor walks them
        var ranges: [HighlightRange] = []
        var i = 0
        var next = 0  // the first Variable that starts at or after i
        func add(_ start: Int, _ token: ColorToken) {
            ranges.append(HighlightRange(range: NSRange(location: start, length: i - start), token: token))
        }
        // A string or comment is coloured around the Variables it holds.
        func addAroundVariables(_ start: Int, _ token: ColorToken) {
            var from = start
            var k = next
            while k < variables.count, variables[k].location < i {
                let v = variables[k]
                if v.location > from { ranges.append(HighlightRange(range: NSRange(location: from, length: v.location - from), token: token)) }
                from = NSMaxRange(v)
                k += 1
            }
            if from < i { ranges.append(HighlightRange(range: NSRange(location: from, length: i - from), token: token)) }
        }
        func starts(_ s: String, at j: Int) -> Bool { Self.starts(s, in: u, at: j) }
        lex: while i < u.count {
            let start = i
            while next < variables.count, variables[next].location < i { next += 1 }
            if next < variables.count, variables[next].location == i {
                i = NSMaxRange(variables[next])
                continue
            }
            switch u[i] {
            case unit(" "), unit("\t"), unit("\n"), unit("\r"):
                i += 1
            case unit("#"):
                while i < u.count, u[i] != unit("\n"), u[i] != unit("\r") { i += 1 }
                addAroundVariables(start, .textTertiary)
            case unit("\"") where starts("\"\"\"", at: i):
                i += 3
                while i < u.count, !starts("\"\"\"", at: i) { i += starts("\\\"\"\"", at: i) ? 4 : 1 }
                i = min(i + 3, u.count)
                addAroundVariables(start, .jsonString)
            case unit("\""):
                i = stringEnd(u, from: i, endsAtLine: true)
                addAroundVariables(start, .jsonString)
            case unit("."):
                guard starts("...", at: i) else { break lex }
                i += 3
                add(start, .jsonPunctuation)
            case unit("{"), unit("}"), unit("("), unit(")"), unit("["), unit("]"), unit(":"), unit("!"),
                unit("="), unit("|"), unit("&"), unit("@"), unit(","):
                i += 1
                add(start, .jsonPunctuation)
            case unit("$"):
                i += 1
                while i < u.count, isGraphQLNameChar(u[i]) { i += 1 }
                guard i > start + 1 else { break lex }
                add(start, .jsonNull)
            case unit("-"), unit("0")...unit("9"):
                i += 1
                guard u[start] != unit("-") || (i < u.count && (unit("0")...unit("9")).contains(u[i])) else { break lex }
                while i < u.count, isNumberPart(u[i]) { i += 1 }
                add(start, .jsonNumber)
            case unit("a")...unit("z"), unit("A")...unit("Z"), unit("_"):
                while i < u.count, isGraphQLNameChar(u[i]) { i += 1 }
                switch String(decoding: u[start..<i], as: UTF16.self) {
                case "query", "mutation", "subscription", "fragment", "on", "true", "false": add(start, .jsonBoolean)
                case "null": add(start, .jsonNull)
                default: add(start, .jsonKey)
                }
            default:
                break lex
            }
        }
        return ranges
    }

    private static func isGraphQLNameChar(_ c: UInt16) -> Bool {
        (unit("a")...unit("z")).contains(c) || (unit("A")...unit("Z")).contains(c) || (unit("0")...unit("9")).contains(c) || c == unit("_")
    }

    private static func unit(_ char: Unicode.Scalar) -> UInt16 { UInt16(char.value) }

    private static func json(_ u: [UInt16]) -> [HighlightRange] {
        var ranges: [HighlightRange] = []
        var i = 0
        func add(_ start: Int, _ token: ColorToken) {
            ranges.append(HighlightRange(range: NSRange(location: start, length: i - start), token: token))
        }
        while i < u.count {
            let start = i
            switch u[i] {
            case unit("\""):
                i = stringEnd(u, from: i)
                var next = i
                while next < u.count, isSpace(u[next]) { next += 1 }
                add(start, next < u.count && u[next] == unit(":") ? .jsonKey : .jsonString)
            case unit("{") where i + 1 < u.count && u[i + 1] == unit("{"):
                i += 2
                while i < u.count, u[i] != unit("}") { i += 1 }
                i = min(i + 2, u.count)
            case unit("{"), unit("}"), unit("["), unit("]"), unit(","), unit(":"):
                i += 1
                add(start, .jsonPunctuation)
            case unit("-"), unit("0")...unit("9"):
                i += 1
                while i < u.count, isNumberPart(u[i]) { i += 1 }
                add(start, .jsonNumber)
            case unit("a")...unit("z"):
                while i < u.count, (unit("a")...unit("z")).contains(u[i]) { i += 1 }
                switch String(decoding: u[start..<i], as: UTF16.self) {
                case "true", "false": add(start, .jsonBoolean)
                case "null": add(start, .jsonNull)
                default: break
                }
            default:
                i += 1
            }
        }
        return ranges
    }

    /// Past the closing quote, skipping escapes; the end of the text if it never closes, or with
    /// `endsAtLine` the end of the line (the line break is not part of the string).
    private static func stringEnd(_ u: [UInt16], from start: Int, endsAtLine: Bool = false) -> Int {
        var i = start + 1
        while i < u.count {
            if endsAtLine, u[i] == unit("\n") || u[i] == unit("\r") { return i }
            if u[i] == unit("\\") {
                i += endsAtLine && i + 1 < u.count && (u[i + 1] == unit("\n") || u[i + 1] == unit("\r")) ? 1 : 2
                continue
            }
            if u[i] == unit("\"") { return i + 1 }
            i += 1
        }
        return u.count
    }

    private static func starts(_ prefix: String, in u: [UInt16], at j: Int) -> Bool {
        var j = j
        for c in prefix.utf16 {
            guard j < u.count, u[j] == c else { return false }
            j += 1
        }
        return true
    }

    private static func isSpace(_ c: UInt16) -> Bool {
        c == unit(" ") || c == unit("\t") || c == unit("\n") || c == unit("\r")
    }

    private static func isNumberPart(_ c: UInt16) -> Bool {
        (unit("0")...unit("9")).contains(c) || c == unit(".") || c == unit("e") || c == unit("E") || c == unit("+") || c == unit("-")
    }

    private static func xml(_ u: [UInt16]) -> [HighlightRange] {
        var ranges: [HighlightRange] = []
        var i = 0
        func add(_ start: Int, _ end: Int, _ token: ColorToken) {
            ranges.append(HighlightRange(range: NSRange(location: start, length: end - start), token: token))
        }
        while i < u.count {
            guard u[i] == unit("<") else { i += 1; continue }
            if starts("<!--", in: u, at: i) {
                i += 4
                while i < u.count, !starts("-->", in: u, at: i) { i += 1 }
                i = min(i + 3, u.count)
                continue
            }
            // `<name`, `</name` or `<?name`: the opener and the name are one tag range.
            let start = i
            i += 1
            if i < u.count, u[i] == unit("/") || u[i] == unit("?") || u[i] == unit("!") { i += 1 }
            while i < u.count, isNameChar(u[i]) { i += 1 }
            add(start, i, .xmlTag)
            while i < u.count {
                let c = u[i]
                if c == unit(">") {
                    add(i, i + 1, .xmlTag)
                    i += 1
                    break
                }
                if (c == unit("/") || c == unit("?")), i + 1 < u.count, u[i + 1] == unit(">") {
                    add(i, i + 2, .xmlTag)
                    i += 2
                    break
                }
                if c == unit("=") {
                    add(i, i + 1, .jsonPunctuation)
                    i += 1
                } else if c == unit("\"") || c == unit("'") {
                    let valueStart = i
                    i += 1
                    while i < u.count, u[i] != c { i += 1 }
                    i = min(i + 1, u.count)
                    add(valueStart, i, .xmlValue)
                } else if isNameChar(c) {
                    let nameStart = i
                    while i < u.count, isNameChar(u[i]) { i += 1 }
                    add(nameStart, i, .xmlAttribute)
                } else {
                    i += 1
                }
            }
        }
        return ranges
    }

    private static func isNameChar(_ c: UInt16) -> Bool {
        (unit("a")...unit("z")).contains(c) || (unit("A")...unit("Z")).contains(c) || (unit("0")...unit("9")).contains(c)
            || c == unit("-") || c == unit("_") || c == unit(":") || c == unit(".") || c > 0x7F
    }
}

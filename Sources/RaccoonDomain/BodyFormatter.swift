import Foundation

/// Re-indents a raw JSON or XML body by 2 spaces and changes nothing else: key order, number
/// spelling, string escapes, attributes and every `{{name}}` stay as typed. Text is returned as
/// it is. Hand-written, because a decode and re-encode through Foundation reorders keys and
/// respells numbers (`1.50` → `1.5`).
public enum BodyFormatter {
    public static func format(_ text: String, kind: RawKind) throws(FormatError) -> String {
        switch kind {
        case .json:
            var formatter = JSONFormatter(Array(text))
            return try formatter.document()
        case .xml:
            return try XMLFormatter.format(Array(text))
        case .text:
            return text
        }
    }

    /// 1-based line and column of `index`, counting Characters.
    fileprivate static func error(at index: Int, in chars: [Character]) -> FormatError {
        var (line, column) = (1, 1)
        for char in chars[..<min(index, chars.count)] {
            if char.isNewline { (line, column) = (line + 1, 1) } else { column += 1 }
        }
        return .notValid(line: line, column: column)
    }
}

private struct JSONFormatter {
    let chars: [Character]
    var i = 0
    var out = ""

    init(_ chars: [Character]) {
        self.chars = chars
    }

    mutating func document() throws(FormatError) -> String {
        try value(depth: 0)
        skipSpace()
        guard i == chars.count else { throw fail() }
        return out
    }

    private func fail() -> FormatError {
        BodyFormatter.error(at: i, in: chars)
    }

    private var current: Character? { i < chars.count ? chars[i] : nil }

    private mutating func skipSpace() {
        while let char = current, char.isWhitespace { i += 1 }
    }

    private mutating func value(depth: Int) throws(FormatError) {
        skipSpace()
        guard let char = current else { throw fail() }
        switch char {
        case "{" where i + 1 < chars.count && chars[i + 1] == "{": try variable()
        case "{": try container(close: "}", depth: depth, isObject: true)
        case "[": try container(close: "]", depth: depth, isObject: false)
        case "\"": try string()
        case _ where char == "-" || (char.isASCII && char.isNumber): try number()
        case "t": try literal("true")
        case "f": try literal("false")
        case "n": try literal("null")
        default: throw fail()
        }
    }

    /// An object or an array: one member per line, `{}` and `[]` when empty.
    private mutating func container(close: Character, depth: Int, isObject: Bool) throws(FormatError) {
        out.append(chars[i])
        i += 1
        skipSpace()
        if current == close {
            out.append(close)
            i += 1
            return
        }
        let indent = String(repeating: "  ", count: depth + 1)
        while true {
            out += "\n" + indent
            skipSpace()
            if isObject {
                switch current {
                case "\"": try string()
                case "{": try variable()
                default: throw fail()
                }
                skipSpace()
                guard current == ":" else { throw fail() }
                i += 1
                out += ": "
            }
            try value(depth: depth + 1)
            skipSpace()
            switch current {
            case ",":
                out += ","
                i += 1
            case close:
                out += "\n" + String(repeating: "  ", count: depth) + String(close)
                i += 1
                return
            default:
                throw fail()
            }
        }
    }

    /// `{{name}}` stands where a value or a key would, copied as typed.
    private mutating func variable() throws(FormatError) {
        let start = i
        i += 2
        while let char = current, char != "{", char != "}" { i += 1 }
        guard current == "}", i + 1 < chars.count, chars[i + 1] == "}" else { throw fail() }
        i += 2
        out += String(chars[start..<i])
    }

    /// Copied as written, escapes included.
    private mutating func string() throws(FormatError) {
        let start = i
        i += 1
        while true {
            guard let char = current else { throw fail() }
            if char == "\"" { break }
            if char.unicodeScalars.first!.value < 0x20 { throw fail() }
            if char == "\\" {
                i += 1
                switch current {
                case "\"", "\\", "/", "b", "f", "n", "r", "t": i += 1
                case "u":
                    i += 1
                    for _ in 0..<4 {
                        guard let hex = current, hex.isHexDigit else { throw fail() }
                        i += 1
                    }
                default: throw fail()
                }
                continue
            }
            i += 1
        }
        i += 1
        out += String(chars[start..<i])
    }

    /// `-? (0 | [1-9][0-9]*) (. [0-9]+)? ([eE] [+-]? [0-9]+)?`, copied as written.
    private mutating func number() throws(FormatError) {
        let start = i
        if current == "-" { i += 1 }
        if current == "0" {
            i += 1
        } else {
            try digits()
        }
        if current == "." {
            i += 1
            try digits()
        }
        if current == "e" || current == "E" {
            i += 1
            if current == "+" || current == "-" { i += 1 }
            try digits()
        }
        out += String(chars[start..<i])
    }

    private mutating func digits() throws(FormatError) {
        guard let char = current, char.isASCII, char.isNumber else { throw fail() }
        while let char = current, char.isASCII, char.isNumber { i += 1 }
    }

    private mutating func literal(_ word: String) throws(FormatError) {
        for char in word {
            guard current == char else { throw fail() }
            i += 1
        }
        out += word
    }
}

private enum XMLFormatter {
    enum Kind {
        case open(name: String), close(name: String), selfClosing, other, text
    }

    struct Token {
        var kind: Kind
        var source: String
        var start: Int
    }

    static func format(_ chars: [Character]) throws(FormatError) -> String {
        let tokens = try tokenize(chars)
        var lines: [String] = []
        var open: [String] = []
        var t = 0
        while t < tokens.count {
            let token = tokens[t]
            let indent = String(repeating: "  ", count: open.count)
            switch token.kind {
            case .open(let name):
                // An element holding only text, or nothing, stays on one line.
                if let (inner, end) = textOnly(tokens, after: t, name: name) {
                    lines.append(indent + token.source + inner + tokens[end].source)
                    t = end + 1
                    continue
                }
                lines.append(indent + token.source)
                open.append(name)
            case .close(let name):
                guard open.last == name else { throw BodyFormatter.error(at: token.start, in: chars) }
                open.removeLast()
                lines.append(String(repeating: "  ", count: open.count) + token.source)
            case .selfClosing, .other, .text:
                lines.append(indent + token.source)
            }
            t += 1
        }
        guard open.isEmpty else { throw BodyFormatter.error(at: chars.count, in: chars) }
        return lines.joined(separator: "\n")
    }

    /// The text between `<name>` and its `</name>`, when nothing else is in between.
    private static func textOnly(_ tokens: [Token], after t: Int, name: String) -> (String, Int)? {
        var end = t + 1
        var inner = ""
        if end < tokens.count, case .text = tokens[end].kind {
            inner = tokens[end].source
            end += 1
        }
        guard end < tokens.count, case .close(let closing) = tokens[end].kind, closing == name else { return nil }
        return (inner, end)
    }

    /// Tags as written, and text trimmed; whitespace-only text is dropped.
    private static func tokenize(_ chars: [Character]) throws(FormatError) -> [Token] {
        var tokens: [Token] = []
        var i = 0
        func until(_ end: String, from start: Int) throws(FormatError) -> Int {
            let end = Array(end)
            var j = start
            while j + end.count <= chars.count {
                if Array(chars[j..<j + end.count]) == end { return j + end.count }
                j += 1
            }
            throw BodyFormatter.error(at: chars.count, in: chars)
        }
        func starts(_ prefix: String, at j: Int) -> Bool {
            let prefix = Array(prefix)
            return j + prefix.count <= chars.count && Array(chars[j..<j + prefix.count]) == prefix
        }
        while i < chars.count {
            let start = i
            if chars[i] != "<" {
                while i < chars.count, chars[i] != "<" { i += 1 }
                let text = String(chars[start..<i]).trimmingCharacters(in: .whitespacesAndNewlines)
                if !text.isEmpty { tokens.append(Token(kind: .text, source: text, start: start)) }
                continue
            }
            if starts("<!--", at: i) {
                i = try until("-->", from: i + 4)
            } else if starts("<![CDATA[", at: i) {
                i = try until("]]>", from: i + 9)
            } else if starts("<?", at: i) {
                i = try until("?>", from: i + 2)
            } else {
                // A tag ends at the first `>` outside quotes.
                var quote: Character?
                i += 1
                while true {
                    guard i < chars.count else { throw BodyFormatter.error(at: chars.count, in: chars) }
                    let char = chars[i]
                    i += 1
                    if let open = quote { if char == open { quote = nil } } else if char == "\"" || char == "'" { quote = char } else if char == ">" { break }
                }
            }
            let source = String(chars[start..<i])
            tokens.append(Token(kind: kind(of: source), source: source, start: start))
        }
        return tokens
    }

    private static func kind(of tag: String) -> Kind {
        if tag.hasPrefix("<!") || tag.hasPrefix("<?") { return .other }
        if tag.hasSuffix("/>") { return .selfClosing }
        let isClose = tag.hasPrefix("</")
        let name = String(tag.dropFirst(isClose ? 2 : 1).prefix { !$0.isWhitespace && $0 != ">" && $0 != "/" })
        return isClose ? .close(name: name) : .open(name: name)
    }
}

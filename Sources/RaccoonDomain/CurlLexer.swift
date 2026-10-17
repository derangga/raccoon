/// Whether a paste into the URL bar is a Curl Import or an ordinary paste.
public enum CurlDetector {
    /// The first word, after leading whitespace, is `curl`.
    public static func isCurl(_ text: String) -> Bool {
        let text = text.drop(while: \.isWhitespace)
        guard text.hasPrefix("curl") else { return false }
        return text.dropFirst(4).first.map(\.isWhitespace) ?? true
    }
}

/// The part of POSIX sh a pasted curl command uses. Foundation has no shell lexer
/// (environment-facts.md), so this is written by hand.
public enum CurlLexer {
    /// The words of the first command whose first word is `curl`, and how many other curl
    /// commands the text held. Commands split on an unquoted `;` or newline in the same pass that
    /// reads the words, so quotes are tracked in one place.
    public static func commands(_ text: String) throws(CurlImportError) -> (words: [String], skipped: Int) {
        var lexer = Lexer(chars: Array(text))
        let curls = try lexer.commands().filter { $0.first == "curl" }
        return (curls.first ?? [], max(curls.count - 1, 0))
    }

    /// curl reads a short cluster one option per character until one that takes a value, which
    /// takes the rest of the cluster: `-fsSL` is four switches, `-XPOST` is `-X POST`. The word
    /// after an option that takes a value is that value, even when it starts with `-`.
    public static func expandShortFlags(_ words: [String]) -> [String] {
        var expanded: [String] = []
        var words = words.makeIterator()
        while let word = words.next() {
            guard let name = CurlFlags.name(word) else {
                expanded.append(word)
                continue
            }
            if word.hasPrefix("--") {
                expanded.append(word)
                if CurlFlags.takesValue.contains(String(name)), let value = words.next() { expanded.append(value) }
                continue
            }
            var rest = name
            while let option = rest.popFirst() {
                expanded.append("-" + String(option))
                guard CurlFlags.takesValue.contains(String(option)) else { continue }
                if !rest.isEmpty {
                    expanded.append(String(rest))
                } else if let value = words.next() {
                    expanded.append(value)
                }
                break
            }
        }
        return expanded
    }
}

private struct Lexer {
    let chars: [Character]
    var i = 0

    mutating func commands() throws(CurlImportError) -> [[String]] {
        var commands: [[String]] = []
        var words: [String] = []
        // nil until a word starts, so '' is an empty word and not no word.
        var word: String?
        func endWord() {
            if let done = word { words.append(done) }
            word = nil
        }
        func endCommand() {
            endWord()
            if !words.isEmpty { commands.append(words) }
            words = []
        }

        while i < chars.count {
            let c = chars[i]
            i += 1
            switch c {
            case " ", "\t":
                endWord()
            case ";":
                endCommand()
            case _ where c.isNewline:
                endCommand()
            case "\\":
                // `\` + newline joins lines; with spaces before the newline (a copy from a doc) it
                // still does, and the spaces separate words.
                var j = i
                while j < chars.count, chars[j] == " " || chars[j] == "\t" { j += 1 }
                if j < chars.count, chars[j].isNewline {
                    if j > i { endWord() }
                    i = j + 1
                } else if i < chars.count {
                    word = (word ?? "") + String(chars[i])
                    i += 1
                }
            case "'":
                word = (word ?? "") + (try singleQuoted())
            case "\"":
                word = (word ?? "") + (try doubleQuoted())
            case "$" where i < chars.count && chars[i] == "'":
                i += 1
                word = (word ?? "") + (try dollarQuoted())
            default:
                word = (word ?? "") + String(c)
            }
        }
        endCommand()
        return commands
    }

    /// The opening quote, 1-based, for the message.
    private func unterminated(_ opening: Int) -> CurlImportError {
        .unterminatedQuote(position: opening + 1)
    }

    /// `'…'`: every character literal, no escapes.
    private mutating func singleQuoted() throws(CurlImportError) -> String {
        let opening = i - 1
        guard let close = chars[i...].firstIndex(of: "'") else { throw unterminated(opening) }
        defer { i = close + 1 }
        return String(chars[i..<close])
    }

    /// `"…"`: `\` escapes only `$`, `` ` ``, `"`, `\` and a newline; before anything else it is a
    /// backslash.
    private mutating func doubleQuoted() throws(CurlImportError) -> String {
        let opening = i - 1
        var text = ""
        while i < chars.count {
            let c = chars[i]
            i += 1
            switch c {
            case "\"":
                return text
            case "\\" where i < chars.count:
                let next = chars[i]
                if next.isNewline {
                    i += 1
                } else if "$`\"\\".contains(next) {
                    text.append(next)
                    i += 1
                } else {
                    text.append(c)
                }
            default:
                text.append(c)
            }
        }
        throw unterminated(opening)
    }

    /// `$'…'`: ANSI-C escapes, what Chrome's Copy as cURL writes.
    private mutating func dollarQuoted() throws(CurlImportError) -> String {
        let opening = i - 2
        var text = ""
        while i < chars.count {
            let c = chars[i]
            i += 1
            guard c == "\\", i < chars.count else {
                if c == "'" { return text }
                text.append(c)
                continue
            }
            let next = chars[i]
            i += 1
            switch next {
            case "n": text.append("\n")
            case "t": text.append("\t")
            case "r": text.append("\r")
            case "a": text.append("\u{07}")
            case "b": text.append("\u{08}")
            case "e", "E": text.append("\u{1B}")
            case "f": text.append("\u{0C}")
            case "v": text.append("\u{0B}")
            case "\\", "'", "\"", "?": text.append(next)
            case "x": text.append(hex(maxDigits: 2) ?? "\\x")
            case "u": text.append(hex(maxDigits: 4) ?? "\\u")
            case "U": text.append(hex(maxDigits: 8) ?? "\\U")
            default: text += "\\" + String(next)
            }
        }
        throw unterminated(opening)
    }

    /// Up to `maxDigits` hex digits as one scalar, or nil (nothing consumed) when there are none.
    private mutating func hex(maxDigits: Int) -> String? {
        let digits = chars[i...].prefix(maxDigits).prefix(while: \.isHexDigit)
        guard let value = UInt32(String(digits), radix: 16), let scalar = Unicode.Scalar(value) else { return nil }
        i += digits.count
        return String(scalar)
    }
}

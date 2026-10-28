import Foundation

extension Highlighter {
    /// The Curl pane's colors (curl.md, The Curl pane): the words CurlRenderer writes, by what
    /// each one is. Never fails: half a command colors what it recognises. `{{name}}` is left out
    /// of every range for the Variable highlight drawn on top.
    public static func curl(_ command: String) -> [HighlightRange] {
        let u = Array(command.utf16)
        var ranges: [HighlightRange] = []
        func add(_ start: Int, _ end: Int, _ token: ColorToken) {
            var from = start
            var i = start
            while i + 1 < end {
                guard u[i] == unit("{"), u[i + 1] == unit("{"), let close = variableEnd(u, from: i + 2, before: end) else {
                    i += 1
                    continue
                }
                if i > from { ranges.append(HighlightRange(range: NSRange(location: from, length: i - from), token: token)) }
                (from, i) = (close, close)
            }
            if end > from { ranges.append(HighlightRange(range: NSRange(location: from, length: end - from), token: token)) }
        }
        /// `name: value`, or `name;` for an empty one.
        func header(_ from: Int, _ to: Int) {
            if let colon = u[from..<to].firstIndex(of: unit(":")) {
                add(from, colon, .jsonKey)
                add(colon, colon + 1, .jsonPunctuation)
                var value = colon + 1
                while value < to, u[value] == unit(" ") { value += 1 }
                add(value, to, .jsonString)
            } else if to > from, u[to - 1] == unit(";") {
                add(from, to - 1, .jsonKey)
                add(to - 1, to, .jsonPunctuation)
            } else {
                add(from, to, .jsonKey)
            }
        }

        var i = 0
        var isFirstWord = true
        /// The flag whose value the next word is.
        var valueOf: Substring?
        while i < u.count {
            if isSpace(u[i]) {
                i += 1
                continue
            }
            // A `\` before a line break continues the command.
            if u[i] == unit("\\"), i + 1 >= u.count || u[i + 1] == unit("\n") || u[i + 1] == unit("\r") {
                add(i, i + 1, .jsonPunctuation)
                i += 1
                continue
            }
            let start = i
            var isQuoted = false
            while i < u.count, isQuoted || !isSpace(u[i]) {
                if u[i] == unit("'") { isQuoted.toggle() } else if !isQuoted, u[i] == unit("\\") { i += 1 }
                i += 1
            }
            let end = min(i, u.count)
            let word = String(decoding: u[start..<end], as: UTF16.self)
            // The quotes that open and close the word are punctuation; a `'\''` between them is content.
            let opens = u[start] == unit("'")
            let closes = opens && !isQuoted && end - start > 1 && u[end - 1] == unit("'")
            let (from, to) = (start + (opens ? 1 : 0), end - (closes ? 1 : 0))
            if opens { add(start, start + 1, .jsonPunctuation) }

            if let flag = valueOf {
                valueOf = nil
                switch flag {
                case "X", "request": add(from, to, .method(String(decoding: u[from..<to], as: UTF16.self)))
                case "H", "header", "proxy-header": header(from, to)
                case "url": add(from, to, .text)
                default: add(from, to, .jsonString)
                }
            } else if !opens, let name = CurlFlags.name(word) {
                add(start, end, .curlFlag)
                if CurlFlags.takesValue.contains(String(name)) { valueOf = name }
            } else if isFirstWord, word == "curl" {
                add(start, end, .curlFlag)
            } else {
                add(from, to, .text)
            }
            if closes { add(end - 1, end, .jsonPunctuation) }
            isFirstWord = false
        }
        return ranges
    }

    /// Past the `}}` that closes a `{{name`, if it closes before `end` with nothing but name
    /// characters in between.
    private static func variableEnd(_ u: [UInt16], from start: Int, before end: Int) -> Int? {
        var i = start
        while i < end, isVariableNameChar(u[i]) { i += 1 }
        return i > start && i + 2 <= end && u[i] == unit("}") && u[i + 1] == unit("}") ? i + 2 : nil
    }

    private static func isVariableNameChar(_ c: UInt16) -> Bool {
        (unit("a")...unit("z")).contains(c) || (unit("A")...unit("Z")).contains(c) || (unit("0")...unit("9")).contains(c)
            || c == unit("_") || c == unit("-") || c == unit(".")
    }

    private static func unit(_ char: Unicode.Scalar) -> UInt16 { UInt16(char.value) }

    private static func isSpace(_ c: UInt16) -> Bool {
        c == unit(" ") || c == unit("\t") || c == unit("\n") || c == unit("\r")
    }
}

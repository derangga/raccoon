import Foundation

/// One styled stretch of a Request's Docs. The range is in UTF-16 units, as text storage takes it.
public struct DocsStyleRange: Equatable, Sendable {
    public var range: NSRange
    public var style: DocsStyle.Style

    public init(range: NSRange, style: DocsStyle.Style) {
        self.range = range
        self.style = style
    }
}

/// Styled ranges for the Docs editor (docs.md). Total: the editor styles half-typed text, so an
/// unmatched mark is plain text and nothing here ever changes a character. Ranges come in text
/// order; where two overlap, the later one is drawn over the earlier.
public enum DocsStyle {
    public enum Style: Equatable, Sendable {
        /// `#`, `**`, `*`, a backtick, a fence line, `[` and `](url)`: dimmed, never removed.
        case mark
        /// 1 to 6 `#`; the text after them.
        case heading(level: Int)
        case bold, italic
        /// Inline code, without its backticks.
        case code
        /// The lines between two fences, or to the end when the fence is never closed.
        case codeBlock
        case listMarker
        case quoteMark
        /// The text after `>`.
        case quote
        /// The text of `[text](url)`; `url` only for `http` and `https`, the ones a click opens.
        case link(url: String?)
    }

    public static func ranges(_ text: String) -> [DocsStyleRange] {
        var scan = Scan(u: Array(text.utf16))
        var start = 0
        while start <= scan.u.count {
            var end = start
            while end < scan.u.count, scan.u[end] != 10 { end += 1 }
            // A CRLF line (a pasted or imported description) ends before its CR.
            scan.line(start, end > start && scan.u[end - 1] == 13 ? end - 1 : end)
            start = end + 1
        }
        scan.finish()
        return scan.out
    }

    private struct Scan {
        let u: [UInt16]
        var out: [DocsStyleRange] = []
        /// Where the open fenced block's first and last content characters are.
        var block: (start: Int, end: Int)?
        var inBlock = false

        init(u: [UInt16]) { self.u = u }

        private static let (space, tab) = (UInt16(32), UInt16(9))
        private func char(_ c: Unicode.Scalar) -> UInt16 { UInt16(c.value) }
        private func isBlank(_ i: Int) -> Bool { u[i] == Self.space || u[i] == Self.tab }

        private mutating func add(_ from: Int, _ to: Int, _ style: Style) {
            if to > from { out.append(DocsStyleRange(range: NSRange(location: from, length: to - from), style: style)) }
        }

        mutating func finish() { closeBlock() }

        private mutating func closeBlock() {
            if let block { add(block.start, block.end, .codeBlock) }
            block = nil
            inBlock = false
        }

        mutating func line(_ from: Int, _ to: Int) {
            var i = from
            while i < to, isBlank(i) { i += 1 }
            if to - i >= 3, u[i] == char("`"), u[i + 1] == char("`"), u[i + 2] == char("`") {
                if inBlock { closeBlock() } else { inBlock = true }
                add(i, to, .mark)
                return
            }
            if inBlock {
                block = (block?.start ?? from, to)
                return
            }
            guard i < to else { return }
            if u[i] == char("#") {
                var j = i
                while j < to, u[j] == char("#") { j += 1 }
                if j - i <= 6, j < to, isBlank(j) {
                    add(i, j, .mark)
                    let level = j - i
                    while j < to, isBlank(j) { j += 1 }
                    add(j, to, .heading(level: level))
                    return
                }
            }
            if u[i] == char(">") {
                add(i, i + 1, .quoteMark)
                var j = i + 1
                if j < to, isBlank(j) { j += 1 }
                add(j, to, .quote)
                inline(j, to)
                return
            }
            let marker = listMarkerEnd(i, to)
            if marker > i {
                add(i, marker, .listMarker)
                inline(marker, to)
                return
            }
            inline(i, to)
        }

        /// `-`, `*`, `+` or digits with `.` or `)`, then a space: where the marker ends, or `from`.
        private func listMarkerEnd(_ from: Int, _ to: Int) -> Int {
            var j = from
            if [char("-"), char("*"), char("+")].contains(u[j]) {
                j += 1
            } else {
                while j < to, (char("0")...char("9")).contains(u[j]) { j += 1 }
                guard j > from, j - from <= 9, j < to, u[j] == char(".") || u[j] == char(")") else { return from }
                j += 1
            }
            return j < to && isBlank(j) ? j : from
        }

        // shortcut: no nesting (italic inside bold, code inside a link) and no `_` emphasis, which
        // snake_case names in Docs would trip; upgrade when Docs need them.
        private mutating func inline(_ from: Int, _ to: Int) {
            var i = from
            while i < to {
                switch u[i] {
                case char("`"):
                    if let close = (i + 2..<max(to, i + 2)).first(where: { u[$0] == char("`") }) {
                        add(i, i + 1, .mark)
                        add(i + 1, close, .code)
                        add(close, close + 1, .mark)
                        i = close + 1
                    } else {
                        i += 1
                    }
                case char("*"):
                    i = emphasis(at: i, to)
                case char("["):
                    i = link(at: i, to)
                default:
                    i += 1
                }
            }
        }

        /// `**bold**` or `*italic*` from the `*` at `i`: the index to go on from.
        private mutating func emphasis(at i: Int, _ to: Int) -> Int {
            let width = i + 1 < to && u[i + 1] == char("*") ? 2 : 1
            let open = i + width
            guard open < to, !isBlank(open) else { return open }
            let close = (open + 1..<max(to, open + 1)).first { j in
                guard u[j] == char("*"), !isBlank(j - 1) else { return false }
                return width == 2 ? j + 1 < to && u[j + 1] == char("*") : !(j + 1 < to && u[j + 1] == char("*"))
            }
            guard let close else { return open }
            add(i, open, .mark)
            add(open, close, width == 2 ? .bold : .italic)
            add(close, close + width, .mark)
            return close + width
        }

        /// `[text](url)` from the `[` at `i`: the index to go on from.
        private mutating func link(at i: Int, _ to: Int) -> Int {
            guard let textEnd = (i + 1..<to).first(where: { u[$0] == char("]") }),
                  textEnd > i + 1, textEnd + 1 < to, u[textEnd + 1] == char("("),
                  let urlEnd = (textEnd + 2..<to).first(where: { u[$0] == char(")") }),
                  urlEnd > textEnd + 2, !(textEnd + 2..<urlEnd).contains(where: isBlank)
            else { return i + 1 }
            let url = String(decoding: u[textEnd + 2..<urlEnd], as: UTF16.self)
            let opens = ["http://", "https://"].contains { url.lowercased().hasPrefix($0) }
            add(i, i + 1, .mark)
            add(i + 1, textEnd, .link(url: opens ? url : nil))
            add(textEnd, urlEnd + 1, .mark)
            return urlEnd + 1
        }
    }
}

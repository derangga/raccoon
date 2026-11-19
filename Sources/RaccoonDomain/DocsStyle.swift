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
/// order, a style's range before the ranges inside it and its closing mark after them; where two
/// overlap, the later one is drawn over the earlier.
public enum DocsStyle {
    public enum Style: Equatable, Sendable {
        /// `#`, `**`, `*`, `~~`, a backtick, `[` and `](url)`: dimmed, never removed.
        case mark
        /// 1 to 6 `#`; the text after them.
        case heading(level: Int)
        case bold, italic
        /// The text between `~~` and `~~`.
        case strikethrough
        /// Inline code, without its backticks.
        case code
        /// A fence line, whole: the three backticks and any info string. `language` is the trimmed info
        /// string of an opening fence, nil when empty and for a closing fence.
        case fence(language: String?)
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
                var language: String?
                if inBlock {
                    closeBlock()
                } else {
                    inBlock = true
                    let info = String(decoding: u[i + 3..<to], as: UTF16.self).trimmingCharacters(in: .whitespaces)
                    language = info.isEmpty ? nil : info
                }
                add(i, to, .fence(language: language))
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
                    inline(j, to)
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

        // shortcut: no `_` emphasis, which snake_case names in Docs would trip; upgrade when Docs need it.
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
                case char("*"), char("~"):
                    i = emphasis(at: i, to)
                case char("["):
                    i = link(at: i, to)
                default:
                    i += 1
                }
            }
        }

        /// `***both***`, `**bold**`, `*italic*` or `~~strikethrough~~` from the `*` or `~` at `i`, and
        /// the styles inside it: the index to go on from.
        private mutating func emphasis(at i: Int, _ to: Int) -> Int {
            let mark = u[i]
            var run = 1
            while i + run < to, u[i + run] == mark { run += 1 }
            if mark == char("~"), run == 1 { return i + 1 }
            var width = run == 3 && mark == char("*") ? 3 : run >= 2 ? 2 : 1
            var open = i + width
            guard open < to, !isBlank(open) else { return open }
            var found = close(of: mark, width: width, after: open, to)
            // `***` that does not close as one is a Bold with a lone `*` in it.
            if found == nil, width == 3 {
                (width, open) = (2, i + 2)
                found = close(of: mark, width: 2, after: open, to)
            }
            guard let found else { return open }
            add(i, open, .mark)
            let styles: [Style] = width == 3 ? [.bold, .italic] : [width == 1 ? .italic : mark == char("~") ? .strikethrough : .bold]
            for style in styles { add(open, found.start, style) }
            inline(open, found.start)
            add(found.start, found.start + found.width, .mark)
            return found.start + found.width
        }

        /// The closing mark for an opening one that ends at `open`: where it starts and how wide it is.
        /// A closing mark follows a non-blank. Runs of `*` count whole, so `**a *b***` closes its Italic
        /// with the first `*` of the last three and its Bold with the other two.
        private func close(of mark: UInt16, width: Int, after open: Int, _ to: Int) -> (start: Int, width: Int)? {
            var j = open + 1
            while j < to {
                guard u[j] == mark else { j += 1; continue }
                var run = 1
                while j + run < to, u[j + run] == mark { run += 1 }
                if !isBlank(j - 1) {
                    switch (width, run) {
                    case (1, 1): return (j, 1)
                    case (1, 3...): return (j + run - 1, 1)
                    case (2, 3) where mark == char("*") && (open..<j).filter({ u[$0] == mark }).count % 2 == 1: return (j + 1, 2)
                    case (2, 2...), (3, 3...): return (j, width)
                    default: break
                    }
                }
                j += run
            }
            return nil
        }

        /// `[text](url)` from the `[` at `i`: the index to go on from.
        private mutating func link(at i: Int, _ to: Int) -> Int {
            // The text ends at the first `]` that a `(` follows, so a `]` inside the text is text.
            guard let textEnd = (i + 1..<to).first(where: { u[$0] == char("]") && $0 + 1 < to && u[$0 + 1] == char("(") }),
                  textEnd > i + 1, !(i + 1..<textEnd).contains(where: { u[$0] == char("[") }),
                  let urlEnd = (textEnd + 2..<to).first(where: { u[$0] == char(")") }),
                  urlEnd > textEnd + 2, !(textEnd + 2..<urlEnd).contains(where: isBlank)
            else { return i + 1 }
            let url = String(decoding: u[textEnd + 2..<urlEnd], as: UTF16.self)
            let opens = ["http://", "https://"].contains { url.lowercased().hasPrefix($0) }
            add(i, i + 1, .mark)
            add(i + 1, textEnd, .link(url: opens ? url : nil))
            inline(i + 1, textEnd)
            add(textEnd, urlEnd + 1, .mark)
            return urlEnd + 1
        }
    }
}

import Foundation

/// The format commands of the Docs editor (docs.md): each edits the markdown and keeps the
/// selection on the same visible text. Total: a command that does not apply gives nil and the
/// editor does what it does by itself. Ranges are UTF-16, as in `DocsStyle`.
public enum DocsEdit {
    public enum Inline: Hashable, Sendable { case bold, italic, strikethrough, code }
    /// Headings are 1 to 3.
    public enum Block: Equatable, Sendable { case paragraph, heading(Int), bullet, numbered, quote, codeBlock }

    public enum Command: Equatable, Sendable {
        case toggle(Inline)
        case block(Block)
        /// An empty URL removes the link at the caret and keeps its text.
        case link(url: String)
        /// Return.
        case newline
        /// Delete with an empty selection.
        case deleteBackward
    }

    public struct Result: Equatable, Sendable {
        public var text: String
        public var selection: NSRange

        public init(text: String, selection: NSRange) {
            self.text = text
            self.selection = selection
        }
    }

    /// What the toolbar shows.
    public struct State: Equatable, Sendable {
        public var block: Block
        public var inline: Set<Inline>
        public var link: String?

        public init(block: Block, inline: Set<Inline>, link: String?) {
            self.block = block
            self.inline = inline
            self.link = link
        }
    }

    public static func apply(_ command: Command, to text: String, selection: NSRange) -> Result? {
        guard let doc = Doc(text, selection) else { return nil }
        switch command {
        case .toggle(let inline): return doc.toggle(inline)
        case .block(.codeBlock): return doc.codeBlock()
        case .block(let block): return doc.setBlock(block)
        case .link(let url): return doc.link(url.trimmingCharacters(in: .whitespacesAndNewlines))
        case .newline: return doc.newline()
        case .deleteBackward: return doc.deleteBackward()
        }
    }

    /// The caret's (first selected) line's block, the inline styles covering the selection, and the
    /// URL of a link the caret is in.
    public static func state(_ text: String, selection: NSRange) -> State {
        guard let doc = Doc(text, selection) else { return State(block: .paragraph, inline: [], link: nil) }
        let line = doc.index(of: doc.s)
        var block = Block.paragraph
        if doc.fences.contains(where: { $0.open <= line && line <= $0.close ?? doc.lines.count - 1 }) {
            block = .codeBlock
        } else if let mark = doc.mark(doc.lines[line]) {
            block = if case .heading(let level) = mark.block { .heading(min(level, 3)) } else { mark.block }
        }
        let inline = Set(Inline.all.filter { doc.covering($0.style) != nil })
        return State(block: block, inline: inline, link: doc.link().map { doc.url($0.mark) })
    }
}

extension DocsEdit.Inline {
    fileprivate static let all: [Self] = [.bold, .italic, .strikethrough, .code]

    fileprivate var marks: String {
        switch self {
        case .bold: "**"
        case .italic: "*"
        case .strikethrough: "~~"
        case .code: "`"
        }
    }

    fileprivate var style: DocsStyle.Style {
        switch self {
        case .bold: .bold
        case .italic: .italic
        case .strikethrough: .strikethrough
        case .code: .code
        }
    }
}

/// One replacement in the text. `before`: a position at `loc` stays before the new text.
private struct Edit {
    var loc: Int
    var old: Int
    var new: String
    var before = false
}

private struct Line {
    var start: Int
    /// Before the line break and its CR.
    var end: Int
    /// After the line break.
    var next: Int
}

private struct Mark {
    var block: DocsEdit.Block
    var start: Int
    /// After the marker and the blank that follows it.
    var end: Int
}

/// The text of one command, split into lines once.
private struct Doc {
    let u: [UInt16]
    let s: Int
    let e: Int
    let lines: [Line]
    let ranges: [DocsStyleRange]
    /// Fenced blocks as line indexes; `close` is nil while the fence is never closed.
    let fences: [(open: Int, close: Int?)]

    init?(_ text: String, _ selection: NSRange) {
        u = Array(text.utf16)
        guard selection.location != NSNotFound, selection.location >= 0, selection.length >= 0,
              selection.location + selection.length <= u.count else { return nil }
        (s, e) = (selection.location, selection.location + selection.length)
        var lines: [Line] = []
        var fences: [(open: Int, close: Int?)] = []
        var start = 0
        while start <= u.count {
            var end = start
            while end < u.count, u[end] != 10 { end += 1 }
            let line = Line(start: start, end: end > start && u[end - 1] == 13 ? end - 1 : end, next: end + 1)
            var i = line.start
            while i < line.end, Self.isBlank(u[i]) { i += 1 }
            if line.end - i >= 3, u[i...i + 2].allSatisfy({ $0 == 96 }) {
                if let last = fences.last, last.close == nil { fences[fences.count - 1].close = lines.count } else { fences.append((lines.count, nil)) }
            }
            lines.append(line)
            start = end + 1
        }
        (self.lines, self.fences, ranges) = (lines, fences, DocsStyle.ranges(text))
    }

    static func isBlank(_ c: UInt16) -> Bool { c == 32 || c == 9 }

    func index(of position: Int) -> Int { lines.lastIndex { $0.start <= position } ?? 0 }

    func inFence(_ line: Int) -> Bool {
        fences.contains { $0.open <= line && line <= $0.close ?? lines.count - 1 }
    }

    /// The lines the selection touches; a selection ending right after a line break leaves the next out.
    var touched: [Line] {
        lines[index(of: s)...index(of: e > s && u[e - 1] == 10 ? e - 1 : e)].map { $0 }
    }

    func indentEnd(_ line: Line) -> Int {
        var i = line.start
        while i < line.end, Self.isBlank(u[i]) { i += 1 }
        return i
    }

    /// The heading, list or quote mark of a line (the true heading level, 1 to 6).
    func mark(_ line: Line) -> Mark? {
        let start = indentEnd(line)
        guard start < line.end else { return nil }
        var j = start
        if u[j] == 35 {
            while j < line.end, u[j] == 35 { j += 1 }
            guard j - start <= 6, j < line.end, Self.isBlank(u[j]) else { return nil }
            let level = j - start
            while j < line.end, Self.isBlank(u[j]) { j += 1 }
            return Mark(block: .heading(level), start: start, end: j)
        }
        if u[j] == 62 {
            j += 1
            if j < line.end, Self.isBlank(u[j]) { j += 1 }
            return Mark(block: .quote, start: start, end: j)
        }
        var block = DocsEdit.Block.bullet
        if [45, 42, 43].contains(u[j]) {
            j += 1
        } else {
            while j < line.end, (48...57).contains(u[j]) { j += 1 }
            guard j > start, j - start <= 9, j < line.end, u[j] == 46 || u[j] == 41 else { return nil }
            j += 1
            block = .numbered
        }
        guard j < line.end, Self.isBlank(u[j]) else { return nil }
        return Mark(block: block, start: start, end: j + 1)
    }

    /// Applies the edits, given in text order, and maps the selection through them unless one is given.
    func result(_ edits: [Edit], selection: NSRange? = nil) -> DocsEdit.Result? {
        guard !edits.isEmpty else { return nil }
        var out: [UInt16] = []
        var at = 0
        for edit in edits {
            out += u[at..<edit.loc] + Array(edit.new.utf16)
            at = edit.loc + edit.old
        }
        out += u[at...]
        func map(_ p: Int) -> Int {
            var shift = 0
            for edit in edits {
                guard p > edit.loc || (p == edit.loc && !edit.before) else { break }
                let n = edit.new.utf16.count
                if p < edit.loc + edit.old { return edit.loc + shift + n }
                shift += n - edit.old
            }
            return p + shift
        }
        let range = selection ?? NSRange(location: map(s), length: map(e) - map(s))
        return DocsEdit.Result(text: String(decoding: out, as: UTF16.self), selection: range)
    }

    // MARK: inline

    /// The first range of `style` that holds the selection.
    func covering(_ style: DocsStyle.Style) -> NSRange? {
        ranges.first { $0.style == style && $0.range.location <= s && e <= NSMaxRange($0.range) }?.range
    }

    func toggle(_ inline: DocsEdit.Inline) -> DocsEdit.Result? {
        let m = inline.marks
        let w = m.utf16.count
        // Already that style: the selection is inside it, or is the whole of it with its marks.
        let found = covering(inline.style)
            ?? ranges.first { $0.style == inline.style && $0.range.location - w == s && NSMaxRange($0.range) + w == e }?.range
        if let r = found {
            return result([Edit(loc: r.location - w, old: w, new: ""), Edit(loc: NSMaxRange(r), old: w, new: "")])
        }
        var (from, to) = (s, e)
        if s == e {
            func isWord(_ c: UInt16) -> Bool { Unicode.Scalar(c).map { CharacterSet.alphanumerics.contains($0) } ?? false }
            while from > 0, isWord(u[from - 1]) { from -= 1 }
            while to < u.count, isWord(u[to]) { to += 1 }
        } else {
            // A mark next to a blank is not a mark, so the selection's blank ends stay outside.
            var (a, b) = (from, to)
            while a < b, Self.isBlank(u[a]) { a += 1 }
            while b > a, Self.isBlank(u[b - 1]) { b -= 1 }
            if a < b { (from, to) = (a, b) }
        }
        // shortcut: a selection over several lines gets one pair, which draws as text; upgrade when Docs need it.
        return result(
            [Edit(loc: from, old: 0, new: m), Edit(loc: to, old: 0, new: m, before: true)],
            selection: s < e ? NSRange(location: from + w, length: to - from) : nil)
    }

    // MARK: block

    func setBlock(_ block: DocsEdit.Block) -> DocsEdit.Result? {
        if case .heading(let level) = block, !(1...3).contains(level) { return nil }
        let all = touched
        let filled = all.filter { indentEnd($0) < $0.end }
        let targets = filled.isEmpty ? all : filled
        let remove = block == .paragraph || targets.allSatisfy { mark($0)?.block == block }
        var edits: [Edit] = []
        for (n, line) in targets.enumerated() {
            let old = mark(line)
            let new: String
            switch block {
            case _ where remove: new = ""
            case .heading(let level): new = String(repeating: "#", count: level) + " "
            case .bullet: new = "- "
            case .numbered: new = "\(n + 1). "
            case .quote: new = "> "
            case .paragraph, .codeBlock: new = ""
            }
            let loc = old?.start ?? indentEnd(line)
            let length = old.map { $0.end - $0.start } ?? 0
            if length > 0 || !new.isEmpty { edits.append(Edit(loc: loc, old: length, new: new)) }
        }
        return result(edits)
    }

    func codeBlock() -> DocsEdit.Result? {
        let first = index(of: s)
        if let fence = fences.first(where: { $0.open <= first && first <= $0.close ?? lines.count - 1 }) {
            func drop(_ line: Line, after: Line?) -> Edit {
                // The last line has no break after it, so the one before goes instead.
                if line.next > u.count, line.start > 0, after.map({ $0.next != line.start }) ?? true {
                    return Edit(loc: line.start - 1, old: line.next - line.start, new: "")
                }
                return Edit(loc: line.start, old: min(line.next, u.count) - line.start, new: "")
            }
            let open = lines[fence.open]
            let close = fence.close.map { lines[$0] }
            return result([drop(open, after: nil)] + (close.map { [drop($0, after: open)] } ?? []))
        }
        let all = touched
        return result([
            Edit(loc: all[0].start, old: 0, new: "```\n"),
            Edit(loc: all[all.count - 1].end, old: 0, new: "\n```", before: true),
        ])
    }

    // MARK: link

    /// The link the selection is in: its text and its `](url)`.
    func link() -> (text: NSRange, mark: NSRange)? {
        for (i, r) in ranges.enumerated() {
            guard case .link = r.style, r.range.location <= s, e <= NSMaxRange(r.range),
                  i + 1 < ranges.count, ranges[i + 1].style == .mark, ranges[i + 1].range.location == NSMaxRange(r.range)
            else { continue }
            return (r.range, ranges[i + 1].range)
        }
        return nil
    }

    func url(_ mark: NSRange) -> String {
        String(decoding: u[mark.location + 2..<NSMaxRange(mark) - 1], as: UTF16.self)
    }

    func link(_ raw: String) -> DocsEdit.Result? {
        // A space or a parenthesis would end the `(url)` early.
        let url = raw.replacingOccurrences(of: " ", with: "%20").replacingOccurrences(of: "(", with: "%28")
            .replacingOccurrences(of: ")", with: "%29")
        if let (text, mark) = link() {
            if url.isEmpty {
                return result([Edit(loc: text.location - 1, old: 1, new: ""), Edit(loc: NSMaxRange(text), old: mark.length, new: "")])
            }
            return result([Edit(loc: mark.location + 2, old: mark.length - 3, new: url)])
        }
        guard !url.isEmpty else { return nil }
        if s < e {
            return result([Edit(loc: s, old: 0, new: "["), Edit(loc: e, old: 0, new: "](\(url))", before: true)])
        }
        return result([Edit(loc: s, old: 0, new: "[\(raw)](\(url))")], selection: NSRange(location: s + 1, length: raw.utf16.count))
    }

    // MARK: Return and Delete

    func newline() -> DocsEdit.Result? {
        let i = index(of: s)
        let line = lines[i]
        guard s == e, !inFence(i), let m = mark(line), m.block == .bullet || m.block == .numbered, s >= m.end else { return nil }
        if u[m.end..<line.end].allSatisfy(Self.isBlank) {
            return result([Edit(loc: line.start, old: line.end - line.start, new: "")])
        }
        var next = String(decoding: u[line.start..<m.end], as: UTF16.self)
        if m.block == .numbered {
            let digits = u[m.start..<m.end].prefix { (48...57).contains($0) }
            let n = Int(String(decoding: digits, as: UTF16.self)) ?? 0
            let delimiter = String(decoding: [u[m.start + digits.count]], as: UTF16.self)
            next = String(decoding: u[line.start..<m.start], as: UTF16.self) + "\(n + 1)\(delimiter) "
        }
        return result([Edit(loc: s, old: 0, new: "\n" + next)])
    }

    func deleteBackward() -> DocsEdit.Result? {
        let i = index(of: s)
        guard s == e, !inFence(i), let m = mark(lines[i]), s == m.end else { return nil }
        return result([Edit(loc: m.start, old: m.end - m.start, new: "")])
    }
}

import Foundation

/// Where each line of a text starts, in UTF-16 offsets, so a Gutter can number the lines it
/// draws without counting from the top.
public struct LineIndex: Equatable, Sendable {
    /// Always at least one: an empty text has one empty line.
    public let starts: [Int]

    /// Lines break where `NSString.lineRange` breaks them, so the numbers match the text view.
    public init(_ text: String) {
        var starts = [0]
        var offset = 0
        var afterCR = false
        for unit in text.utf16 {
            offset += 1
            switch unit {
            case 0x0A where afterCR: starts[starts.count - 1] = offset
            case 0x0A, 0x0D, 0x2028, 0x2029, 0x85: starts.append(offset)
            default: break
            }
            afterCR = unit == 0x0D
        }
        self.starts = starts
    }

    /// 0-based: the last line starting at or before `offset`.
    public func line(containing offset: Int) -> Int {
        var (low, high) = (0, starts.count)
        while low < high {
            let mid = (low + high) / 2
            if starts[mid] <= offset { low = mid + 1 } else { high = mid }
        }
        return max(low - 1, 0)
    }
}

/// A block of a Pretty body that can be folded onto its opening line.
public struct FoldRegion: Hashable, Sendable {
    public var openLine: Int
    public var closeLine: Int
    /// UTF-16, from the open line's terminator to the close line's first non-space: folded,
    /// it is shown as " … ", so `{` and `}` stay on the one line.
    public var cut: Range<Int>

    public init(openLine: Int, closeLine: Int, cut: Range<Int>) {
        self.openLine = openLine
        self.closeLine = closeLine
        self.cut = cut
    }

    /// By indentation, not by parsing: a line opens a region when the next line is indented
    /// deeper, and the region closes on the first later line indented no deeper. Sound only
    /// for `BodyFormatter`'s output, two spaces a level and one token per line. In line order.
    public static func find(_ text: String, lines: LineIndex) -> [FoldRegion] {
        let units = Array(text.utf16)
        let starts = lines.starts
        let indent = starts.map { start in
            var end = start
            while end < units.count, units[end] == 0x20 { end += 1 }
            return end - start
        }
        func contentEnd(_ line: Int) -> Int {
            var end = line + 1 < starts.count ? starts[line + 1] : units.count
            while end > starts[line], [0x0A, 0x0D, 0x2028, 0x2029, 0x85].contains(units[end - 1]) { end -= 1 }
            return end
        }
        var open: [Int] = []
        var regions: [FoldRegion] = []
        for line in starts.indices {
            while let top = open.last, indent[top] >= indent[line] {
                open.removeLast()
                if top + 1 < line, indent[top + 1] > indent[top] {
                    regions.append(FoldRegion(openLine: top, closeLine: line, cut: contentEnd(top) ..< starts[line] + indent[line]))
                }
            }
            open.append(line)
        }
        return regions.sorted { $0.openLine < $1.openLine }
    }
}

/// Which Fold Regions are folded, by open line. View state: every send starts with none.
public struct FoldSet: Equatable, Sendable {
    public private(set) var folded: Set<Int>

    /// Fold All passes every region; an empty set is Unfold All.
    public init(folding regions: [FoldRegion] = []) {
        folded = Set(regions.map(\.openLine))
    }

    public func isFolded(_ region: FoldRegion) -> Bool { folded.contains(region.openLine) }

    public mutating func toggle(_ region: FoldRegion) {
        if folded.remove(region.openLine) == nil { folded.insert(region.openLine) }
    }

    /// What ⌥⌘[ folds and ⌥⌘] unfolds: the innermost region around `line` that is, or is
    /// not, folded.
    public func innermost(at line: Int, in regions: [FoldRegion], folded wanted: Bool) -> FoldRegion? {
        regions.last { $0.openLine <= line && line <= $0.closeLine && isFolded($0) == wanted }
    }
}

/// The body as shown: each outermost Folded region's cut replaced by `marker`, and offsets
/// mapped both ways, so Copy reads the body and the Gutter numbers its lines.
public struct FoldedText: Equatable, Sendable {
    public static let marker = " … "
    private static let width = marker.utf16.count

    /// The folded regions not inside another folded one, in text order.
    public let folded: [FoldRegion]
    /// Where each region's marker is shown.
    private let markers: [Int]

    public init(regions: [FoldRegion], folds: FoldSet) {
        var folded: [FoldRegion] = []
        for region in regions where folds.isFolded(region) && folded.last.map({ region.openLine >= $0.closeLine }) ?? true {
            folded.append(region)
        }
        var removed = 0
        markers = folded.map { region in
            defer { removed += region.cut.count - Self.width }
            return region.cut.lowerBound - removed
        }
        self.folded = folded
    }

    /// The last index whose key is at or before `offset`, or nil.
    private static func last(_ keys: some RandomAccessCollection<Int>, atOrBefore offset: Int) -> Int? {
        var (low, high) = (0, keys.count)
        while low < high {
            let mid = (low + high) / 2
            if keys[keys.index(keys.startIndex, offsetBy: mid)] <= offset { low = mid + 1 } else { high = mid }
        }
        return low == 0 ? nil : low - 1
    }

    /// A shown offset in the body; one inside a marker is the start of its cut.
    public func source(_ display: Int) -> Int {
        guard let k = Self.last(markers, atOrBefore: display) else { return display }
        return display < markers[k] + Self.width ? folded[k].cut.lowerBound : display - markers[k] - Self.width + folded[k].cut.upperBound
    }

    /// A body offset as shown; one inside a cut is its marker.
    public func display(_ source: Int) -> Int {
        guard let k = Self.last(folded.lazy.map(\.cut.lowerBound), atOrBefore: source) else { return source }
        return source < folded[k].cut.upperBound ? markers[k] : source - folded[k].cut.upperBound + markers[k] + Self.width
    }

    /// The body text a shown selection covers: one that touches a marker takes its whole cut.
    public func sourceRange(_ display: Range<Int>) -> Range<Int> {
        let end: Int
        if let k = Self.last(markers, atOrBefore: display.upperBound - 1), display.upperBound > markers[k], display.upperBound <= markers[k] + Self.width {
            end = folded[k].cut.upperBound
        } else {
            end = source(display.upperBound)
        }
        return source(display.lowerBound) ..< max(end, source(display.lowerBound))
    }

    public func region(atMarker display: Int) -> FoldRegion? {
        guard let k = Self.last(markers, atOrBefore: display), display < markers[k] + Self.width else { return nil }
        return folded[k]
    }

    /// Inside a folded region, after its opening line: the closing line is shown on that one.
    public func isHidden(line: Int) -> Bool {
        guard let k = Self.last(folded.lazy.map(\.openLine), atOrBefore: line) else { return false }
        return line > folded[k].openLine && line <= folded[k].closeLine
    }

    /// The next line the Gutter numbers: a folded line's closing line is shown on it.
    public func nextLine(after line: Int) -> Int {
        guard let k = Self.last(folded.lazy.map(\.openLine), atOrBefore: line), folded[k].openLine == line else { return line + 1 }
        return folded[k].closeLine + 1
    }
}

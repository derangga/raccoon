import Foundation
import RaccoonDomain
import Testing

struct LineIndexTests {
    @Test(arguments: [
        ("", [0]),
        ("one line", [0]),
        ("a\nb", [0, 2]),
        ("a\n", [0, 2]),
        ("a\r\nb\r\n", [0, 3, 6]),
        ("a\rb", [0, 2]),
        ("a\u{2028}b\u{2029}c\u{85}d", [0, 2, 4, 6]),
        ("😀\nb", [0, 3]),
    ])
    func `lines start where NSString breaks them, in UTF-16`(text: String, starts: [Int]) {
        #expect(LineIndex(text).starts == starts)
    }

    @Test(arguments: [(0, 0), (2, 0), (3, 1), (6, 1), (7, 2), (9, 2)])
    func `an offset is on the last line starting at or before it`(offset: Int, line: Int) {
        #expect(LineIndex("ab\ncde\nfg").line(containing: offset) == line)
    }
}

struct FoldRegionTests {
    static func r(_ open: Int, _ close: Int, _ cut: Range<Int>) -> FoldRegion {
        FoldRegion(openLine: open, closeLine: close, cut: cut)
    }

    @Test(arguments: [
        // Postman's example: chevrons on lines 1 and 3, in 1-based numbers.
        ("{\n  \"id\": 1,\n  \"rating\": {\n    \"rate\": 3.9,\n    \"count\": 120\n  }\n}", [r(0, 6, 1..<65), r(2, 5, 26..<63)]),
        ("[\n  1,\n  [\n    2\n  ]\n]", [r(0, 5, 1..<21), r(2, 4, 10..<19)]),
        ("<a>\n  <b>x</b>\n  <c>\n    <d/>\n  </c>\n</a>", [r(0, 5, 3..<37), r(2, 4, 20..<32)]),
        ("{\n  \"a\": {},\n  \"b\": []\n}", [r(0, 3, 1..<23)]),
        ("{\r\n  \"a\": 1\r\n}", [r(0, 2, 1..<13)]),
        (#"{"a":1}"#, []),
        ("{}", []),
        ("", []),
    ])
    func `a line opens a Fold Region when the next is indented deeper`(text: String, regions: [FoldRegion]) {
        #expect(FoldRegion.find(text, lines: LineIndex(text)) == regions)
    }

    @Test func `a 200,000-line body`() {
        let item = "  {\n    \"a\": 1\n  },\n"
        let text = "[\n" + String(repeating: item, count: 66_666) + "]"
        let lines = LineIndex(text)
        let regions = FoldRegion.find(text, lines: lines)
        #expect(lines.starts.count == 200_000)
        #expect(regions.count == 66_667)
        #expect(regions.first.map { ($0.openLine, $0.closeLine) } ?? (0, 0) == (0, 199_999))
        #expect(regions.last.map { ($0.openLine, $0.closeLine) } ?? (0, 0) == (199_996, 199_998))
    }
}

/// Postman's example: `{` on line 0 closes on line 6, `"rating": {` on line 2 closes on line 5.
private let outer = FoldRegion(openLine: 0, closeLine: 6, cut: 1..<65)
private let rating = FoldRegion(openLine: 2, closeLine: 5, cut: 26..<63)

struct FoldSetTests {
    @Test func `toggling folds, then unfolds`() {
        var folds = FoldSet()
        folds.toggle(rating)
        #expect(folds.isFolded(rating) && !folds.isFolded(outer))
        folds.toggle(rating)
        #expect(folds == FoldSet())
    }

    @Test func `Fold All folds every region`() {
        let folds = FoldSet(folding: [outer, rating])
        #expect(folds.isFolded(outer) && folds.isFolded(rating))
    }

    @Test(arguments: [
        (3, [], false, rating), (1, [], false, outer), (6, [], false, outer),
        (2, [rating], false, outer), (2, [rating], true, rating), (3, [], true, nil),
    ] as [(Int, [FoldRegion], Bool, FoldRegion?)])
    func `the region at the caret is the innermost one around its line`(line: Int, folded: [FoldRegion], wantFolded: Bool, region: FoldRegion?) {
        #expect(FoldSet(folding: folded).innermost(at: line, in: [outer, rating], folded: wantFolded) == region)
    }
}

struct FoldedTextTests {
    let regions = [outer, rating]

    @Test func `nothing folded maps every offset to itself`() {
        let shown = FoldedText(regions: regions, folds: FoldSet())
        #expect(shown.folded.isEmpty)
        #expect(shown.source(40) == 40 && shown.display(40) == 40)
        #expect(shown.nextLine(after: 2) == 3)
    }

    @Test func `a region inside a folded one is not cut twice`() {
        let shown = FoldedText(regions: regions, folds: FoldSet(folding: regions))
        #expect(shown.folded == [outer])
        // "{ … }": the closing brace is shown at 4.
        #expect(shown.source(4) == 65)
        #expect(shown.nextLine(after: 0) == 7)
    }

    // "  \"rating\": { … }" ends line 2; the marker is shown at 26..<29.
    @Test(arguments: [(10, 10), (26, 26), (27, 26), (28, 26), (29, 63), (31, 65)])
    func `a shown offset maps to the body, the marker to the start of its cut`(display: Int, source: Int) {
        #expect(FoldedText(regions: regions, folds: FoldSet(folding: [rating])).source(display) == source)
    }

    @Test(arguments: [(10, 10), (26, 26), (40, 26), (62, 26), (63, 29), (65, 31)])
    func `a body offset maps to what is shown, a folded one to its marker`(source: Int, display: Int) {
        #expect(FoldedText(regions: regions, folds: FoldSet(folding: [rating])).display(source) == display)
    }

    @Test(arguments: [(0..<32, 0..<66), (27..<28, 26..<63), (20..<29, 20..<63), (29..<31, 63..<65), (10..<26, 10..<26)])
    func `a selection across the marker copies the folded lines`(display: Range<Int>, source: Range<Int>) {
        #expect(FoldedText(regions: regions, folds: FoldSet(folding: [rating])).sourceRange(display) == source)
    }

    @Test(arguments: [(2, false), (3, true), (5, true), (6, false)])
    func `a folded region's lines after its opening one are hidden`(line: Int, hidden: Bool) {
        #expect(FoldedText(regions: regions, folds: FoldSet(folding: [rating])).isHidden(line: line) == hidden)
    }

    @Test func `the marker is where a click unfolds, and the Gutter skips the folded lines`() {
        let shown = FoldedText(regions: regions, folds: FoldSet(folding: [rating]))
        #expect(shown.region(atMarker: 27) == rating)
        #expect(shown.region(atMarker: 25) == nil && shown.region(atMarker: 29) == nil)
        #expect(shown.nextLine(after: 2) == 6)
        #expect(shown.nextLine(after: 1) == 2)
    }
}

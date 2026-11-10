import Foundation
@testable import RaccoonDomain
import Testing

struct FindMatchesTests {
    func find(_ query: String, in text: String, cap: Int = FindMatches.cap) -> FindMatches {
        FindMatches(of: query, in: text as NSString, cap: cap)
    }

    @Test(arguments: [
        ("pickle", #"{"id": "big-pickle"}"#, [12 ..< 18]),
        ("PICKLE", "Pickle pickle", [0 ..< 6, 7 ..< 13]),
        ("aa", "aaa", [0 ..< 2, 1 ..< 3]),
        ("x", "abc", []),
        ("", "abc", []),
        ("😀", "a😀b😀", [1 ..< 3, 4 ..< 6]),
        ("b", "😀b", [2 ..< 3]),
    ] as [(String, String, [Range<Int>])])
    func `matches are case-insensitive, literal, overlapping and in UTF-16 offsets`(query: String, text: String, expected: [Range<Int>]) {
        let matches = find(query, in: text)
        #expect(matches.ranges == expected)
        #expect(!matches.capped)
    }

    @Test func `past the cap the matches stop and say so`() {
        let matches = find("a", in: "aaaaa", cap: 3)
        #expect(matches.ranges == [0 ..< 1, 1 ..< 2, 2 ..< 3])
        #expect(matches.capped)
        #expect(!find("a", in: "aaa", cap: 3).capped)
    }

    @Test(arguments: [(0, 0), (1, 1), (3, 1), (4, 2), (6, 2), (7, 0), (100, 0)])
    func `the first match is the one at or after the caret, wrapping`(caret: Int, expected: Int) {
        let matches = find("ab", in: "ab ab ab")
        #expect(matches.first(atOrAfter: caret) == expected)
    }

    @Test func `with no matches there is no first`() {
        #expect(find("z", in: "ab").first(atOrAfter: 0) == nil)
    }

    @Test(arguments: [(0, true, 1), (2, true, 0), (0, false, 2), (1, false, 0)])
    func `next and previous wrap around`(current: Int, forward: Bool, expected: Int) {
        #expect(find("a", in: "aaa").step(current, forward: forward) == expected)
    }

    @Test func `the count reads as the panel shows it`() {
        #expect(find("", in: "abc").count(current: nil) == "")
        #expect(find("z", in: "abc").count(current: nil) == "No results")
        #expect(find("a", in: "a a a").count(current: 1) == "2 of 3")
        #expect(find("a", in: String(repeating: "a", count: 1_500)).count(current: 1_233) == "1,234 of 1,500")
        #expect(find("a", in: "aaaaa", cap: 3).count(current: 0) == "1 of 3+")
        #expect(find("a", in: String(repeating: "a", count: FindMatches.cap + 1)).count(current: 0) == "1 of 10,000+")
    }

    @Test(arguments: [
        (0 ..< 3, 0 ..< 1),
        (2 ..< 9, 1 ..< 3),
        (10 ..< 11, 3 ..< 4),
        (2 ..< 3, 1 ..< 1),
        (20 ..< 30, 4 ..< 4),
    ] as [(Range<Int>, Range<Int>)])
    func `the visible slice is the matches that overlap the visible range`(visible: Range<Int>, expected: Range<Int>) {
        let matches = find("ab", in: "ab ab ab ab")
        #expect(matches.indices(overlapping: visible) == expected)
    }
}

struct FoldSetUnfoldingTests {
    /// Lines 0…6 of `{ "a": { "b": 1 }, "c": [ 2 ] }` laid out two spaces a level.
    let outer = FoldRegion(openLine: 0, closeLine: 6, cut: 1 ..< 60)
    let inner = FoldRegion(openLine: 1, closeLine: 3, cut: 10 ..< 30)
    let sibling = FoldRegion(openLine: 4, closeLine: 6, cut: 40 ..< 58)
    var regions: [FoldRegion] { [outer, inner, sibling] }

    @Test func `a match inside nested folds opens them and leaves the sibling folded`() {
        let unfolded = FoldSet(folding: regions).unfolding(15 ..< 20, in: regions)
        #expect(unfolded == FoldSet(folding: [sibling]))
    }

    @Test func `a match outside every fold changes nothing`() {
        let folds = FoldSet(folding: [inner])
        #expect(folds.unfolding(35 ..< 38, in: regions) == folds)
    }

    @Test func `a match that only touches a cut's edge does not open it`() {
        let folds = FoldSet(folding: [inner])
        #expect(folds.unfolding(30 ..< 32, in: regions) == folds)
        #expect(folds.unfolding(8 ..< 10, in: regions) == folds)
    }

    @Test func `a match straddling a cut's start opens that fold`() {
        #expect(FoldSet(folding: [inner]).unfolding(8 ..< 12, in: regions) == FoldSet())
    }
}

import Foundation
import RaccoonDomain
import Testing

struct SidebarPathTests {
    @Test(arguments: [
        ("Sociolla", []),
        ("A/B", ["A"]),
        ("A/B/C", ["A", "A/B"]),
        ("A/F.json", ["A"]),
        ("A/B/C/F.json", ["A", "A/B", "A/B/C"]),
        ("Beauty 🦝 テスト/Ünï cødé/F.json", ["Beauty 🦝 テスト", "Beauty 🦝 テスト/Ünï cødé"]),
    ] as [(String, [String])])
    func `a path's ancestors are every Collection and Folder above it, outermost first`(path: String, ancestors: [String]) {
        #expect(SidebarPath.ancestors(of: path) == ancestors)
    }
}

struct BreadcrumbOfTests {
    static let id = TreeDecoderTests.id
    static func seg(_ title: String, _ target: String?) -> BreadcrumbSegment { BreadcrumbSegment(title: title, target: target) }

    static func index(_ nodes: [TreeNode], collection: String = "Sociolla") -> DataFolderIndex {
        DataFolderIndex([Collection(name: collection, nodes: nodes)])
    }

    @Test func `a Draft is its Tab title alone, with no target`() {
        let breadcrumb = Breadcrumb.of(source: .draft, title: "/anything/webhooks", index: Self.index([]), lastKnown: nil)
        #expect(breadcrumb.segments == [Self.seg("/anything/webhooks", nil)])
    }

    @Test func `a Draft ignores the last known segments`() {
        let stale = Breadcrumb(segments: [Self.seg("Old", "Old"), Self.seg("Req", "Old/Req.json")])
        #expect(Breadcrumb.of(source: .draft, title: "Draft", index: Self.index([]), lastKnown: stale).segments == [Self.seg("Draft", nil)])
    }

    @Test(arguments: [
        // the Request at a Collection's top: two segments, the second named by the name inside the file
        (
            [TreeNode.request(id(1), name: "Retry Share", method: "GET", path: "Sociolla/retry-share-0001.json")],
            [seg("Sociolla", "Sociolla"), seg("Retry Share", "Sociolla/retry-share-0001.json")]
        ),
        // three Folders deep
        (
            [TreeNode.folder(name: "A", children: [.folder(name: "B", children: [.folder(name: "C", children: [
                .request(id(1), name: "Deep", method: "GET", path: "Sociolla/A/B/C/Deep.json"),
            ])])])],
            [seg("Sociolla", "Sociolla"), seg("A", "Sociolla/A"), seg("B", "Sociolla/A/B"), seg("C", "Sociolla/A/B/C"),
             seg("Deep", "Sociolla/A/B/C/Deep.json")]
        ),
        // spaces, emoji, Japanese
        (
            [TreeNode.folder(name: "Beauty Journal 🦝", children: [
                .request(id(1), name: "PROPFIND Webhooks テスト 🚀", method: "GET", path: "Sociolla/Beauty Journal 🦝/x.json"),
            ])],
            [seg("Sociolla", "Sociolla"), seg("Beauty Journal 🦝", "Sociolla/Beauty Journal 🦝"),
             seg("PROPFIND Webhooks テスト 🚀", "Sociolla/Beauty Journal 🦝/x.json")]
        ),
    ] as [([TreeNode], [BreadcrumbSegment])])
    func `a Request in the index is its Collection, each Folder, then its own name`(nodes: [TreeNode], segments: [BreadcrumbSegment]) {
        let breadcrumb = Breadcrumb.of(source: .request(Self.id(1)), title: "ignored", index: Self.index(nodes), lastKnown: nil)
        #expect(breadcrumb.segments == segments)
    }

    @Test func `after a Folder is renamed in the index the same RequestID gives the new names and paths`() {
        let before = Self.index([.folder(name: "Articles", children: [.request(Self.id(1), name: "Share", method: "GET", path: "Sociolla/Articles/Share.json")])])
        let after = Self.index([.folder(name: "Posts", children: [.request(Self.id(1), name: "Share", method: "GET", path: "Sociolla/Posts/Share.json")])])
        let source = Tab.Source.request(Self.id(1))
        #expect(Breadcrumb.of(source: source, title: "", index: before, lastKnown: nil).segments.map(\.title) == ["Sociolla", "Articles", "Share"])
        #expect(Breadcrumb.of(source: source, title: "", index: after, lastKnown: nil).segments
            == [Self.seg("Sociolla", "Sociolla"), Self.seg("Posts", "Sociolla/Posts"), Self.seg("Share", "Sociolla/Posts/Share.json")])
    }

    @Test func `no entry gives the last known segments`() {
        let known = Breadcrumb(segments: [Self.seg("Sociolla", "Sociolla"), Self.seg("Share", "Sociolla/Share.json")])
        #expect(Breadcrumb.of(source: .request(Self.id(9)), title: "Share", index: Self.index([]), lastKnown: known) == known)
    }

    @Test func `no entry and nothing known gives the Tab's title alone with no target`() {
        let breadcrumb = Breadcrumb.of(source: .request(Self.id(9)), title: "Share", index: Self.index([]), lastKnown: nil)
        #expect(breadcrumb.segments == [Self.seg("Share", nil)])
    }
}

struct BreadcrumbFitTests {
    // separator 10 and ellipsis 8, so a hidden range costs the "…" and one more separator
    @Test(arguments: [
        ([100.0], 10.0, 8.0, 50.0, BreadcrumbFit.all),                       // one: truncation is the view's
        ([100.0, 100], 10, 8, 50, .all),                                     // two: the same
        ([50.0, 50, 50], 10, 8, 170, .all),                                  // 150 + 20 fits exactly
        ([50.0, 50, 50], 10, 8, 169, .collapsed(hidden: 1..<2)),             // 50 + 10 + 8 + 10 + 50 = 128
        ([50.0, 50, 50], 10, 8, 128, .collapsed(hidden: 1..<2)),
        ([50.0, 50, 50, 50], 10, 8, 188, .collapsed(hidden: 1..<2)),         // 150 + 8 + 30
        ([50.0, 50, 50, 50], 10, 8, 187, .collapsed(hidden: 1..<3)),         // nearest the first goes first, then more
        ([50.0, 50, 50, 50, 50], 10, 8, 150, .collapsed(hidden: 1..<4)),
        ([50.0, 50, 50, 50], 10, 8, 20, .collapsed(hidden: 1..<3)),          // too small even then: every middle one
    ] as [([Double], Double, Double, Double, BreadcrumbFit)])
    func `the middle collapses into the ellipsis, nearest the first, until the rest fit`(
        widths: [Double], separator: Double, ellipsis: Double, available: Double, fit: BreadcrumbFit
    ) {
        #expect(Breadcrumb.fit(widths: widths, separator: separator, ellipsis: ellipsis, available: available) == fit)
    }

    @Test func `the ellipsis is counted only when something is hidden`() {
        // Nothing hidden: 100 + 10 + 100 + 10 + 100 = 320 fits in 320 with no ellipsis in the sum.
        #expect(Breadcrumb.fit(widths: [100, 100, 100], separator: 10, ellipsis: 8, available: 320) == .all)
        // One short of that, the ellipsis and its separator are paid for: 100 + 10 + 8 + 10 + 100 = 228.
        #expect(Breadcrumb.fit(widths: [100, 100, 100, 100], separator: 10, ellipsis: 8, available: 228) == .collapsed(hidden: 1..<3))
        #expect(Breadcrumb.fit(widths: [100, 100, 100, 100], separator: 10, ellipsis: 8, available: 227) == .collapsed(hidden: 1..<3))
    }

    @Test func `the hidden range is contiguous and never holds the first or the last index`() {
        for count in 3...9 {
            for available in stride(from: 0.0, through: 600, by: 7) {
                let fit = Breadcrumb.fit(widths: Array(repeating: 60, count: count), separator: 12, ellipsis: 9, available: available)
                if case .collapsed(let hidden) = fit {
                    #expect(hidden.lowerBound == 1 && hidden.upperBound <= count - 1 && !hidden.isEmpty)
                }
            }
        }
    }
}

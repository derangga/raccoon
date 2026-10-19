import Foundation
import RaccoonDomain
import Testing

struct TreeFilterTests {
    static let id = TreeDecoderTests.id
    static let tree = [
        Collection(name: "Payments API", nodes: [
            .folder(name: "Refunds", children: [
                .request(id(1), name: "List refunds", path: "Payments API/Refunds/List refunds.json"),
                .request(id(2), name: "Café order", path: "Payments API/Refunds/Cafe order.json"),
            ]),
            .request(id(3), name: "Create charge", path: "Payments API/Create charge.json"),
            .unreadable(path: "Payments API/Broken refund.json", reason: "Unknown file version 3."),
        ]),
        Collection(name: "Orders", nodes: [
            .request(id(4), name: "注文の返金", path: "Orders/注文の返金.json"),
        ]),
    ]

    @Test func `cafe finds Café, and its ancestors are kept and opened`() {
        let filtered = TreeFilter.matches(Self.tree, "cafe")
        #expect(filtered.collections == [
            Collection(name: "Payments API", nodes: [
                .folder(name: "Refunds", children: [
                    .request(Self.id(2), name: "Café order", path: "Payments API/Refunds/Cafe order.json"),
                ]),
            ]),
        ])
        #expect(filtered.expanded == ["Payments API", "Payments API/Refunds"])
        #expect(filtered.matchedText == ["Payments API/Refunds/Cafe order.json": "Café"])
    }

    @Test func `a matching Folder keeps everything under it`() {
        let filtered = TreeFilter.matches(Self.tree, "REFUNDS")
        #expect(filtered.collections == [
            Collection(name: "Payments API", nodes: [
                .folder(name: "Refunds", children: [
                    .request(Self.id(1), name: "List refunds", path: "Payments API/Refunds/List refunds.json"),
                    .request(Self.id(2), name: "Café order", path: "Payments API/Refunds/Cafe order.json"),
                ]),
            ]),
        ])
        #expect(filtered.matchedText == ["Payments API/Refunds": "Refunds", "Payments API/Refunds/List refunds.json": "refunds"])
    }

    @Test func `unreadable rows match by file name`() {
        let filtered = TreeFilter.matches(Self.tree, "broken")
        #expect(filtered.collections == [
            Collection(name: "Payments API", nodes: [.unreadable(path: "Payments API/Broken refund.json", reason: "Unknown file version 3.")]),
        ])
    }

    @Test(arguments: ["refnd", "POST", "https", "api.example.com"])
    func `no match, and method or URL never match`(query: String) {
        let filtered = TreeFilter.matches(Self.tree, query)
        #expect(filtered.collections.isEmpty)
        #expect(filtered.matchedText.isEmpty)
    }

    @Test func `the matched range is right in a Japanese name`() {
        let filtered = TreeFilter.matches(Self.tree, "返金")
        #expect(filtered.matchedText == ["Orders/注文の返金.json": "返金"])
        #expect(filtered.matchCount == 1)
    }
}

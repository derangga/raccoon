import Foundation
import RaccoonDomain
import Testing

struct TreeFilterTests {
    static let id = TreeDecoderTests.id
    static let tree = [
        Collection(name: "Payments API", nodes: [
            .folder(name: "Refunds", children: [
                .request(id(1), name: "List refunds", method: "GET", path: "Payments API/Refunds/List refunds.json"),
                .request(id(2), name: "Café order", method: "GET", path: "Payments API/Refunds/Cafe order.json"),
            ]),
            .request(id(3), name: "Create charge", method: "GET", path: "Payments API/Create charge.json"),
            .unreadable(path: "Payments API/Broken refund.json", reason: "Unknown file version 3."),
        ]),
        Collection(name: "Orders", nodes: [
            .request(id(4), name: "注文の返金", method: "GET", path: "Orders/注文の返金.json"),
        ]),
    ]

    @Test func `cafe finds Café, and its ancestors are kept and opened`() {
        let filtered = TreeFilter.matches(Self.tree, "cafe")
        #expect(filtered.collections == [
            Collection(name: "Payments API", nodes: [
                .folder(name: "Refunds", children: [
                    .request(Self.id(2), name: "Café order", method: "GET", path: "Payments API/Refunds/Cafe order.json"),
                ]),
            ]),
        ])
        #expect(filtered.expanded == ["Payments API", "Payments API/Refunds"])
        #expect(filtered.matchedText == ["Payments API/Refunds/Cafe order.json": ["Café"]])
    }

    @Test func `a matching Folder keeps everything under it`() {
        let filtered = TreeFilter.matches(Self.tree, "REFUNDS")
        #expect(filtered.collections == [
            Collection(name: "Payments API", nodes: [
                .folder(name: "Refunds", children: [
                    .request(Self.id(1), name: "List refunds", method: "GET", path: "Payments API/Refunds/List refunds.json"),
                    .request(Self.id(2), name: "Café order", method: "GET", path: "Payments API/Refunds/Cafe order.json"),
                ]),
                // A gap match: "refund" and the s of ".json".
                .unreadable(path: "Payments API/Broken refund.json", reason: "Unknown file version 3."),
            ]),
        ])
        #expect(filtered.matchedText == [
            "Payments API/Refunds": ["Refunds"],
            "Payments API/Refunds/List refunds.json": ["refunds"],
            "Payments API/Broken refund.json": ["refund", "s"],
        ])
    }

    @Test func `unreadable rows match by file name`() {
        let filtered = TreeFilter.matches(Self.tree, "broken")
        #expect(filtered.collections == [
            Collection(name: "Payments API", nodes: [.unreadable(path: "Payments API/Broken refund.json", reason: "Unknown file version 3.")]),
        ])
    }

    @Test(arguments: ["graphql", "POST", "https", "api.example.com"])
    func `no match, and method or URL never match`(query: String) {
        let filtered = TreeFilter.matches(Self.tree, query)
        #expect(filtered.collections.isEmpty)
        #expect(filtered.matchedText.isEmpty)
    }

    @Test func `the matched range is right in a Japanese name`() {
        let filtered = TreeFilter.matches(Self.tree, "返金")
        #expect(filtered.matchedText == ["Orders/注文の返金.json": ["返金"]])
        #expect(filtered.matchCount == 1)
    }

    @Test(arguments: [
        ("refnd", "Payments API/Refunds/List refunds.json", ["ref", "nd"]),
        ("crch", "Payments API/Create charge.json", ["Cr", "ch"]),
        ("cfe", "Payments API/Refunds/Cafe order.json", ["C", "fé"]),
        ("注金", "Orders/注文の返金.json", ["注", "金"]),
    ])
    func `letters in order with gaps match, each run highlighted`(query: String, path: String, runs: [String]) {
        let filtered = TreeFilter.matches(Self.tree, query)
        #expect(filtered.matchedText[path] == runs)
    }

    @Test func `a substring is preferred to a gap match`() {
        let filtered = TreeFilter.matches(Self.tree, "charge")
        #expect(filtered.matchedText["Payments API/Create charge.json"] == ["charge"])
    }

    @Test func `a gap match lands on the shortest stretch that holds it`() {
        let filtered = TreeFilter.matches([Collection(name: "C", nodes: [
            .request(Self.id(9), name: "Purge refund cache", method: "PURGE", path: "C/Purge refund cache.json"),
        ])], "refnd")
        #expect(filtered.matchedText["C/Purge refund cache.json"] == ["ref", "nd"])
    }

    @Test func `a Collection matched with gaps keeps only what matches on its own`() {
        let filtered = TreeFilter.matches(Self.tree, "pai")
        #expect(filtered.collections == [Collection(name: "Payments API", nodes: [])])
        #expect(filtered.matchedText == ["Payments API": ["P", "A", "I"]])
        #expect(filtered.expanded.isEmpty)
    }
}

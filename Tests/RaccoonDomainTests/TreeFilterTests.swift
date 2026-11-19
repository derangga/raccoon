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

    static let examples = [
        ExampleSummary(id: ExampleID(UUID(uuidString: "E0000000-0000-4000-8000-000000000001")!), name: "Card declined", status: 402),
        ExampleSummary(id: ExampleID(UUID(uuidString: "E0000000-0000-4000-8000-000000000002")!), name: "Success", status: 200),
    ]
    static let withExamples = [
        Collection(name: "Pay", nodes: [
            .folder(name: "Charges", children: [
                .request(id(1), name: "Create charge", method: "POST", path: "Pay/Charges/Create charge.json", examples: examples),
            ]),
            .request(id(2), name: "Ping", method: "GET", path: "Pay/Ping.json", examples: [examples[0]]),
        ]),
    ]
    static func key(_ path: String, _ example: ExampleSummary) -> String { example.path(in: path) }

    @Test func `an Example's name matches: its Request stays with only that Example, and opens`() {
        let filtered = TreeFilter.matches(Self.withExamples, "declined")
        #expect(filtered.collections == [
            Collection(name: "Pay", nodes: [
                .folder(name: "Charges", children: [
                    .request(Self.id(1), name: "Create charge", method: "POST", path: "Pay/Charges/Create charge.json", examples: [Self.examples[0]]),
                ]),
                .request(Self.id(2), name: "Ping", method: "GET", path: "Pay/Ping.json", examples: [Self.examples[0]]),
            ]),
        ])
        #expect(filtered.expanded == ["Pay", "Pay/Charges", "Pay/Charges/Create charge.json", "Pay/Ping.json"])
        #expect(filtered.matchedText == [
            Self.key("Pay/Charges/Create charge.json", Self.examples[0]): ["declined"],
            "Pay/Ping.json#E0000000-0000-4000-8000-000000000001": ["declined"],
        ])
        #expect(filtered.matchCount == 2)
    }

    @Test func `an Example's name matches with gaps, as a Request's does`() {
        let filtered = TreeFilter.matches(Self.withExamples, "scs")
        #expect(filtered.matchedText[Self.key("Pay/Charges/Create charge.json", Self.examples[1])] == ["S", "c", "s"])
    }

    @Test func `a Request that matched on its own name keeps all its Examples, and stays closed`() {
        let filtered = TreeFilter.matches(Self.withExamples, "create")
        #expect(filtered.collections == [
            Collection(name: "Pay", nodes: [
                .folder(name: "Charges", children: [
                    .request(Self.id(1), name: "Create charge", method: "POST", path: "Pay/Charges/Create charge.json", examples: Self.examples),
                ]),
            ]),
        ])
        #expect(!filtered.expanded.contains("Pay/Charges/Create charge.json"))
    }

    @Test func `a matching Folder keeps its Requests with all their Examples`() {
        let filtered = TreeFilter.matches(Self.withExamples, "charges")
        #expect(filtered.collections == [
            Collection(name: "Pay", nodes: [Self.withExamples[0].nodes[0]]),
        ])
    }

    @Test func `an Example hit under a Request kept by its own name or its Folder's opens that Request`() {
        let declined = ExampleSummary(id: ExampleID(UUID(uuidString: "E0000000-0000-4000-8000-000000000003")!), name: "Charges declined", status: 402)
        let ok = ExampleSummary(id: ExampleID(UUID(uuidString: "E0000000-0000-4000-8000-000000000004")!), name: "Success", status: 200)
        let tree = [Collection(name: "Pay", nodes: [
            .folder(name: "Charges", children: [
                .request(Self.id(1), name: "Refund", method: "GET", path: "Pay/Charges/Refund.json", examples: [declined, ok]),
            ]),
            .request(Self.id(2), name: "Charges refund", method: "GET", path: "Pay/Charges refund.json", examples: [declined, ok]),
            .request(Self.id(3), name: "Charges list", method: "GET", path: "Pay/Charges list.json", examples: [ok]),
        ])]

        let filtered = TreeFilter.matches(tree, "charges")

        // Folder match: all its Requests and Examples kept. Own-name match: the same.
        #expect(filtered.collections == tree.map { Collection(name: $0.name, nodes: [$0.nodes[0], $0.nodes[1], $0.nodes[2]]) })
        #expect(filtered.expanded.isSuperset(of: ["Pay/Charges/Refund.json", "Pay/Charges refund.json"]))
        // Every Example hit counted sits under a Request that is open.
        let hits = filtered.matches.keys.filter { $0.contains("#") }
        #expect(Set(hits.map { String($0.split(separator: "#")[0]) }).isSubset(of: filtered.expanded))
        #expect(hits.count == 2)
        // A Request that matched itself with no Example hit stays closed.
        #expect(!filtered.expanded.contains("Pay/Charges list.json"))
    }
}

import Foundation
import RaccoonDomain
import Testing

struct DataFolderIndexTests {
    static let id = TreeDecoderTests.id

    @Test func `a duplicate RequestID: the second by path order is unreadable`() {
        let index = DataFolderIndex([
            Collection(name: "B", nodes: [.request(Self.id(1), name: "Copy", method: "GET", path: "B/Copy.json")]),
            Collection(name: "A", nodes: [
                .folder(name: "F", children: [.request(Self.id(1), name: "List refunds", method: "GET", path: "A/F/List refunds.json")]),
                .request(Self.id(2), name: "Other", method: "GET", path: "A/Other.json"),
            ]),
        ])
        #expect(index.collections[0].nodes == [.unreadable(path: "B/Copy.json", reason: "Same id as List refunds.json.")])
        #expect(index.path(of: Self.id(1)) == "A/F/List refunds.json")
        #expect(index.path(of: Self.id(2)) == "A/Other.json")
        #expect(index.path(of: Self.id(3)) == nil)
    }

    @Test func `insert puts a Request in its Folder, sorted, and indexes it`() {
        var index = DataFolderIndex([
            Collection(name: "A", nodes: [
                .folder(name: "F", children: [.request(Self.id(1), name: "Zeta", method: "GET", path: "A/F/Zeta.json")]),
            ]),
        ])
        index.insert(Self.id(2), name: "Alpha", method: "GET", path: "A/F/Alpha.json")
        index.insert(Self.id(3), name: "Top", method: "GET", path: "A/Top.json")
        #expect(index.collections == [
            Collection(name: "A", nodes: [
                .folder(name: "F", children: [
                    .request(Self.id(2), name: "Alpha", method: "GET", path: "A/F/Alpha.json"),
                    .request(Self.id(1), name: "Zeta", method: "GET", path: "A/F/Zeta.json"),
                ]),
                .request(Self.id(3), name: "Top", method: "GET", path: "A/Top.json"),
            ]),
        ])
        #expect(index.path(of: Self.id(2)) == "A/F/Alpha.json")
    }
}

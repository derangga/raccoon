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
        #expect(index.name(of: Self.id(1)) == "List refunds")
        #expect(index.name(of: Self.id(3)) == nil)
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
        #expect(index.name(of: Self.id(2)) == "Alpha")
    }

    @Test func `folders are listed as paths in tree order, with the file names each holds`() {
        let index = DataFolderIndex([
            Collection(name: "Auth", nodes: []),
            Collection(name: "Payments API", nodes: [
                .folder(name: "Webhooks", children: [
                    .folder(name: "Old", children: []),
                    .request(Self.id(1), name: "Create webhook", method: "GET", path: "Payments API/Webhooks/Create webhook.json"),
                ]),
                .request(Self.id(2), name: "Refund", method: "GET", path: "Payments API/Refund.json"),
                .unreadable(path: "Payments API/Broken.json", reason: "x"),
            ]),
        ])
        #expect(index.folders == ["Auth", "Payments API", "Payments API/Webhooks", "Payments API/Webhooks/Old"])
        #expect(index.fileNames(in: "Payments API") == ["Refund.json", "Broken.json"])
        #expect(index.fileNames(in: "Payments API/Webhooks") == ["Create webhook.json"])
        #expect(index.fileNames(in: "Nowhere").isEmpty)
    }
}

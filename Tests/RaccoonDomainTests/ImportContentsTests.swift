import Foundation
import RaccoonDomain
import Testing

/// A planned Collection as the folders and files writeDirectory takes, by path inside it.
struct ImportContentsTests {
    static func request(_ n: UInt8, _ name: String) -> Request {
        Request(id: RequestID(UUID(uuid: (n, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0))), name: name, definition: .empty)
    }

    @Test func `Folders and Requests get file names as New Folder and Save give them`() {
        let collection = ImportCollection(name: "Payments API", nodes: [
            .request(Self.request(1, "Create charge")),
            .folder(name: "Refunds", children: [.request(Self.request(2, "List / all")), .folder(name: "Empty", children: [])]),
            .request(Self.request(3, "create CHARGE")),
            .folder(name: "a:b", children: [.request(Self.request(4, "x"))]),
            .request(Self.request(5, "Refunds")),
        ])

        #expect(collection.contents == DataFolderScan(
            files: [
                "Create charge.json": RequestFile.encode(Self.request(1, "Create charge")),
                "Refunds/List - all.json": RequestFile.encode(Self.request(2, "List / all")),
                "create CHARGE 2.json": RequestFile.encode(Self.request(3, "create CHARGE")),
                "a-b/x.json": RequestFile.encode(Self.request(4, "x")),
                "Refunds.json": RequestFile.encode(Self.request(5, "Refunds")),
            ],
            folders: ["Refunds", "Refunds/Empty", "a-b"]
        ))
    }

    @Test func `an empty Folder name is New Folder and an empty Request name is Request`() {
        let collection = ImportCollection(name: "C", nodes: [
            .folder(name: "", children: [.request(Self.request(1, ""))]),
            .folder(name: "", children: []),
            .request(Self.request(2, "")),
        ])

        #expect(collection.contents == DataFolderScan(
            files: [
                "New Folder/Request.json": RequestFile.encode(Self.request(1, "Request")),
                "Request.json": RequestFile.encode(Self.request(2, "Request")),
            ],
            folders: ["New Folder", "New Folder 2"]
        ))
    }
}

extension ImportContentsTests {
    @Test func `a Request's Examples are written in its file`() throws {
        var request = Self.request(1, "r")
        request.examples = [Example(id: ExampleID(UUID()), name: "OK", status: 200, headers: [Row(name: "A", value: "1")], body: .text("b"))]
        let file = try #require(ImportCollection(name: "C", nodes: [.request(request)]).contents.files["r.json"])
        #expect(try RequestFile.decode(file).examples == request.examples)
    }
}

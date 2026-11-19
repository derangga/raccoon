import Foundation
import RaccoonDomain
import Testing

struct TreeDecoderTests {
    static func id(_ n: Int) -> RequestID {
        RequestID(UUID(uuidString: String(format: "00000000-0000-4000-8000-%012d", n))!)
    }

    static func file(_ n: Int, _ name: String, method: String = "GET") -> Data {
        Data(#"{"version": 1, "id": "\#(id(n).rawValue)", "name": "\#(name)", "method": "\#(method)", "url": "https://a.b"}"#.utf8)
    }

    @Test func `top-level folders are Collections, deeper ones Folders, sorted folders first`() {
        let scan = DataFolderScan(
            files: [
                "globals.json": Data("{}".utf8),
                "environments/Dev.json": Data("{}".utf8),
                "Payments API/Refund.json": Self.file(1, "Refund"),
                "Payments API/create.json": Self.file(2, "Create charge"),
                "Payments API/Refunds/List refunds.json": Self.file(3, "List refunds"),
            ],
            folders: ["environments", "Payments API", "Payments API/Refunds", "Payments API/Refunds/Old", "Empty"]
        )
        #expect(TreeDecoder.collections(scan) == [
            Collection(name: "Empty", nodes: []),
            Collection(name: "Payments API", nodes: [
                .folder(name: "Refunds", children: [
                    .folder(name: "Old", children: []),
                    .request(Self.id(3), name: "List refunds", method: "GET", path: "Payments API/Refunds/List refunds.json"),
                ]),
                .request(Self.id(2), name: "Create charge", method: "GET", path: "Payments API/create.json"),
                .request(Self.id(1), name: "Refund", method: "GET", path: "Payments API/Refund.json"),
            ]),
        ])
    }

    @Test(arguments: [
        ("{\n  \"version\": 1,\n  \"name\": \"A\"\n  \"method\": \"GET\"\n}", "Not valid JSON at line 4. Raccoon won't change this file."),
        ("", "Not valid JSON at line 1. Raccoon won't change this file."),
        (#"{"version": 3, "id": "x"}"#, "Unknown file version 3."),
        (#"{"version": 1, "id": "00000000-0000-4000-8000-000000000001", "method": "GET", "url": "x"}"#,
         "Not a Raccoon Request: missing “name”. Raccoon won't change this file."),
        (#"[1, 2]"#, "Not a Raccoon Request: not a JSON object. Raccoon won't change this file."),
    ])
    func `a file that does not decode is an unreadable row with its reason`(contents: String, reason: String) {
        let scan = DataFolderScan(files: ["C/Broken.json": Data(contents.utf8)], folders: ["C"])
        #expect(TreeDecoder.collections(scan) == [Collection(name: "C", nodes: [.unreadable(path: "C/Broken.json", reason: reason)])])
    }

    @Test func `a Request's Examples are listed in file order, with name and status`() throws {
        var request = try RequestFile.decode(Self.file(1, "Refund"))
        let ids = [3, 1, 2].map { ExampleID(UUID(uuidString: "E0000000-0000-4000-8000-00000000000\($0)")!) }
        request.examples = [
            Example(id: ids[0], name: "Declined", status: 402, body: .text("")),
            Example(id: ids[1], name: "ok", status: 200, body: .text("{}")),
            Example(id: ids[2], name: "Gone", status: 500, body: .text("")),
        ]
        let scan = DataFolderScan(files: ["C/Refund.json": RequestFile.encode(request)], folders: ["C"])

        #expect(TreeDecoder.collections(scan) == [Collection(name: "C", nodes: [
            .request(Self.id(1), name: "Refund", method: "GET", path: "C/Refund.json", examples: [
                ExampleSummary(id: ids[0], name: "Declined", status: 402),
                ExampleSummary(id: ids[1], name: "ok", status: 200),
                ExampleSummary(id: ids[2], name: "Gone", status: 500),
            ]),
        ])])
    }

    @Test func `a Request with no Examples has none in the tree`() {
        let scan = DataFolderScan(files: ["C/A.json": Self.file(1, "A")], folders: ["C"])
        #expect(TreeDecoder.collections(scan) == [Collection(name: "C", nodes: [
            .request(Self.id(1), name: "A", method: "GET", path: "C/A.json", examples: []),
        ])])
    }
}

import Foundation
import RaccoonDomain
import Testing

struct CollectionExportTests {
    static func request(_ name: String, path: String = "") -> TreeNode {
        .request(RequestID(UUID()), name: name, method: "GET", path: path)
    }

    @Test func `Folders come first, then Requests and unreadable rows together, each by the name shown, at every depth`() {
        let tree: [TreeNode] = [
            Self.request("Request 10"),
            .unreadable(path: "C/Request 2.json", reason: "Not valid JSON at line 1."),
            .folder(name: "b", children: [Self.request("z"), .folder(name: "Inner", children: []), Self.request("a")]),
            Self.request("Request 1"),
            .folder(name: "A", children: []),
        ]

        let names = CollectionExport.sorted(tree).map(\.name)
        #expect(names == ["A", "b", "Request 1", "Request 2.json", "Request 10"])
        guard case .folder(_, let inner) = CollectionExport.sorted(tree)[1] else {
            Issue.record("b is a Folder")
            return
        }
        #expect(inner.map(\.name) == ["Inner", "a", "z"])
    }

    @Test func `a Collection counts its Requests and every Folder at any depth, in tree order`() {
        func request(_ name: String) -> ExportNode { .request(Request(id: RequestID(UUID()), name: name, definition: .empty)) }
        let collection = ExportCollection(name: "C", nodes: [
            .folder(name: "A", children: [.folder(name: "B", children: [request("deep")]), request("mid")]),
            request("top"),
        ])

        #expect(collection.requests.map(\.name) == ["deep", "mid", "top"])
        #expect(collection.folderCount == 2)
        #expect(ExportCollection(name: "Empty", nodes: []).folderCount == 0)
    }
}

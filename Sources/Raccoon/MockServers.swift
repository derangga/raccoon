import Foundation
import RaccoonDomain
import Synchronization

/// One running Mock Server as the window holds it: what the Collection row and its menu show.
/// The listener and the answering box that go with it are the window's, not part of this value.
struct MockServer: Equatable {
    let collection: String
    let port: UInt16
    var allowsCORS: Bool
    var routes: [MockRoute]

    var url: String { "http://127.0.0.1:\(port)" }
}

/// One line of the Mock Server sheet's route list: a Request, whether or not it has an Example.
struct MockRouteRow: Equatable {
    let method: String
    let path: String
    let exampleCount: Int
}

/// What the listener answers from, off the main actor. Routes and the CORS flag are swapped as
/// whole values under a lock, so a reply never reads a half-updated index.
nonisolated final class MockAnswering: Sendable {
    private struct State {
        var routes: [MockRoute]
        var allowsCORS: Bool
    }

    private let state: Mutex<State>

    init(routes: [MockRoute], allowsCORS: Bool) {
        state = Mutex(State(routes: routes, allowsCORS: allowsCORS))
    }

    func swap(routes: [MockRoute]) {
        state.withLock { $0.routes = routes }
    }

    func swap(allowsCORS: Bool) {
        state.withLock { $0.allowsCORS = allowsCORS }
    }

    func answer(_ head: MockRequestHead) -> MockReply {
        let current = state.withLock { $0 }
        return MockMatch.answer(current.routes, head, allowsCORS: current.allowsCORS)
    }
}

/// What the window reads out of its last scan for a Mock Server.
enum MockServing {
    /// The Collection's remembered settings; no raccoon.json, or one that does not decode, is `.standard`.
    static func settings(for collection: String, in scan: DataFolderScan) -> MockSettings {
        let mocks = scan.files["raccoon.json"].flatMap { try? WorkspaceFile.contents($0).mocks } ?? [:]
        return WorkspaceFile.settings(for: collection, in: mocks)
    }

    /// Whether raccoon.json decodes and holds an entry for the Collection.
    static func hasSettings(for collection: String, in scan: DataFolderScan) -> Bool {
        scan.files["raccoon.json"].flatMap { try? WorkspaceFile.contents($0).mocks[collection] } != nil
    }

    /// The Collection's decodable Requests in sidebar order, from the files as the scan has them: a
    /// Dirty Tab's edits are not here. nil when the Collection is not in the scan.
    private static func requests(for collection: String, in scan: DataFolderScan) -> [Request]? {
        guard let found = TreeDecoder.collections(scan).first(where: { $0.name == collection }) else { return nil }
        func paths(_ nodes: [TreeNode]) -> [String] {
            nodes.flatMap { node -> [String] in
                switch node {
                case .folder(_, let children): paths(children)
                case .request(_, _, _, let path, _): [path]
                case .unreadable: []
                }
            }
        }
        return paths(found.nodes).compactMap { path in
            scan.files[path].flatMap { try? RequestFile.decode($0) }
        }
    }

    /// The routes of the Collection's Requests in sidebar order. A Request that does not decode has
    /// no route. nil when the Collection is not in the scan.
    static func routes(for collection: String, in scan: DataFolderScan) -> [MockRoute]? {
        requests(for: collection, in: scan).map(MockRoutes.build)
    }

    /// One row per Request, those with no Example too (they are listed, not served); [] when the
    /// Collection is not in the scan.
    static func rows(for collection: String, in scan: DataFolderScan) -> [MockRouteRow] {
        (requests(for: collection, in: scan) ?? []).map {
            MockRouteRow(method: $0.definition.method, path: MockRoutes.path(of: $0.definition.url), exampleCount: $0.examples.count)
        }
    }
}

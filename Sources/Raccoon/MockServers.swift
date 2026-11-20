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

    /// The routes of the Collection's Requests in sidebar order, from the files as the scan has
    /// them: a Dirty Tab's edits are not here. A Request that does not decode has no route. nil
    /// when the Collection is not in the scan.
    static func routes(for collection: String, in scan: DataFolderScan) -> [MockRoute]? {
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
        return MockRoutes.build(paths(found.nodes).compactMap { path in
            scan.files[path].flatMap { try? RequestFile.decode($0) }
        })
    }
}

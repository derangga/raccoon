import Foundation
@testable import Raccoon
import RaccoonData
import RaccoonDomain
import RaccoonTesting
import Testing

/// The same models the composition root builds, from the §9 test implementations only.
@MainActor
struct CompositionTests {
    let temp = FileManager.default.temporaryDirectory.appending(path: "raccoon-\(UUID())")

    func makeTab() -> TabModel {
        TabModel(transport: ScriptedTransport(.failure(.timedOut)), secrets: InMemorySecretStore(), instants: FixedInstantSource(.now))
    }

    @Test func `a window builds entirely from test implementations and starts with one empty Draft`() {
        let window = WindowModel(
            dataFolder: DiskDataFolderStore(root: temp.appending(path: "Raccoon")),
            folderWatch: ManualFolderWatch(),
            sessionStore: DiskSessionStore(directory: temp.appending(path: "Support")),
            secrets: InMemorySecretStore(),
            newTab: makeTab
        )

        #expect(window.tabs.count == 1)
        #expect(window.tabs[0].tab.source == .draft)
        #expect(window.tabs[0].tab.definition == .empty)
        #expect(window.tabs[0].tab.baseline == nil)
        #expect(window.tabs[0].tab.response == .idle)
        #expect(!FileManager.default.fileExists(atPath: temp.path))  // building touches no disk
    }

    @Test func `a TabModel holds no DataFolderStore`() {
        #expect(Mirror(reflecting: makeTab()).children.allSatisfy { !($0.value is any DataFolderStore) })
    }
}

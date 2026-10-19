import Foundation
@testable import Raccoon
import RaccoonData
import RaccoonDomain
import RaccoonTesting
import Testing

/// Relaunch from session.json, over a real DiskSessionStore in a temp dir.
@MainActor
struct RelaunchTests {
    let directory = FileManager.default.temporaryDirectory.appending(path: "raccoon-\(UUID())")
    var store: DiskSessionStore { DiskSessionStore(directory: directory) }

    func makeWindow() -> WindowModel {
        WindowModel(
            dataFolder: DiskDataFolderStore(root: directory.appending(path: "Raccoon")), folderWatch: ManualFolderWatch(),
            sessionStore: store, secrets: InMemorySecretStore(), instants: FixedInstantSource(.now),
            makeTab: {
                TabModel(transport: ScriptedTransport(.failure(.timedOut)), secrets: InMemorySecretStore(), files: DictionaryFileReading([:]),
                         instants: FixedInstantSource(.now), clipboard: RecordingClipboardWriter())
            }
        )
    }

    func draft(_ url: String) -> TabSnapshot {
        var definition = RequestDefinition.empty
        definition.url = url
        return TabSnapshot(id: TabID(UUID()), source: .draft, definition: definition, baseline: nil)
    }

    func asides() throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: directory.path).filter { $0.hasPrefix("session.corrupt-") }
    }

    @Test func `three Drafts come back in order with the same selection`() throws {
        let drafts = [draft("https://a.example/1"), draft("https://b.example/2"), draft("")]
        try store.write(SessionFile.encode(Session(tabs: drafts, selected: drafts[1].id, activeEnvironment: nil)))

        let window = makeWindow()
        window.relaunch()

        #expect(window.tabs.map(\.tab.snapshot) == drafts)
        #expect(window.selected == drafts[1].id)
        #expect(window.tabs.allSatisfy { $0.tab.response == .idle })
    }

    @Test func `a stored selection that names no Tab selects the first`() throws {
        let drafts = [draft("https://a.example"), draft("https://b.example")]
        try store.write(SessionFile.encode(Session(tabs: drafts, selected: TabID(UUID()), activeEnvironment: nil)))
        let window = makeWindow()
        window.relaunch()
        #expect(window.selected == drafts[0].id)
    }

    @Test func `a Session with no Tabs opens one empty Draft`() throws {
        try store.write(SessionFile.encode(Session(tabs: [], selected: nil, activeEnvironment: nil)))
        let window = makeWindow()
        window.relaunch()
        #expect(window.tabs.count == 1)
        #expect(window.tabs[0].tab.definition == .empty)
        #expect(window.selected == window.tabs[0].tab.id)
    }

    @Test func `no Session is one empty Draft, and nothing is written`() throws {
        let window = makeWindow()
        window.relaunch()
        #expect(window.tabs.count == 1)
        #expect(window.tabs[0].tab.source == .draft && window.tabs[0].tab.definition == .empty)
        #expect(!FileManager.default.fileExists(atPath: directory.path))
    }

    @Test func `an undecodable Session is renamed, not deleted, and the window opens one empty Draft`() async throws {
        try store.write(Data("{ not json".utf8))
        let window = makeWindow()
        window.relaunch()

        #expect(window.tabs.count == 1)
        #expect(window.tabs[0].tab.definition == .empty)
        let aside = try #require(try asides().first)
        #expect(aside.hasSuffix(".json"))
        #expect(FileManager.default.contents(atPath: directory.appending(path: aside).path) == Data("{ not json".utf8))
        #expect(try store.read() == nil)
    }
}

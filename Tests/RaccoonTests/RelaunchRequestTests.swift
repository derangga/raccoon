import Foundation
@testable import Raccoon
import RaccoonData
import RaccoonDomain
import RaccoonTesting
import Testing

/// Relaunch with Request Tabs: SessionStore and DataFolderStore over temp dirs.
@MainActor
struct RelaunchRequestTests {
    let temp = FileManager.default.temporaryDirectory.appending(path: "raccoon-\(UUID())")
    var root: URL { temp.appending(path: "Raccoon") }
    var store: DiskSessionStore { DiskSessionStore(directory: temp.appending(path: "Support")) }
    static let charge = OpenRequestTests.charge
    var file: URL { root.appending(path: "Payments API/Create charge.json") }

    func makeWindow() -> WindowModel {
        WindowModel(
            dataFolder: .test(root), folderWatch: ManualFolderWatch(), sessionStore: store,
            secrets: InMemorySecretStore(), instants: FixedInstantSource(.now),
            makeTab: {
                TabModel(transport: ScriptedTransport(.failure(.timedOut)), secrets: InMemorySecretStore(), files: DictionaryFileReading([:]),
                         instants: FixedInstantSource(.now), clipboard: RecordingClipboardWriter())
            }
        )
    }

    var pulled: RequestDefinition {
        var definition = Self.charge.definition
        definition.url = "https://api.example.com/v2/charges"
        return definition
    }

    var edited: RequestDefinition {
        var definition = Self.charge.definition
        definition.headers.append(Row(name: "X-Mine", value: "1"))
        return definition
    }

    /// The Session holds one Request Tab with `definition` over `baseline`; the disk holds `disk`.
    func relaunch(definition: RequestDefinition, baseline: RequestDefinition, disk: RequestDefinition?) throws -> TabModel {
        if let disk {
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try RequestFile.encode(Request(id: Self.charge.id, name: "Create charge", definition: disk)).write(to: file)
        }
        let snapshot = TabSnapshot(id: TabID(UUID()), source: .request(Self.charge.id), definition: definition, baseline: baseline)
        try store.write(SessionFile.encode(Session(tabs: [snapshot], selected: snapshot.id, activeEnvironment: nil)))
        let window = makeWindow()
        window.loadDataFolder()
        window.relaunch()
        return try #require(window.tabs.first)
    }

    @Test func `the file as the Session left it: restored as it was`() throws {
        let tab = try relaunch(definition: edited, baseline: Self.charge.definition, disk: Self.charge.definition)
        #expect(tab.tab.source == .request(Self.charge.id))
        #expect(tab.tab.definition == edited)
        #expect(tab.tab.baseline == Self.charge.definition)
        #expect(!tab.tab.isChangedOnDisk)
    }

    @Test func `the file changed and the Tab was clean: it takes the file silently`() throws {
        let tab = try relaunch(definition: Self.charge.definition, baseline: Self.charge.definition, disk: pulled)
        #expect(tab.tab.definition == pulled)
        #expect(tab.tab.baseline == pulled)
        #expect(!tab.tab.isChangedOnDisk)
    }

    @Test func `the file changed under Dirty edits: they are kept, Changed on Disk`() throws {
        let tab = try relaunch(definition: edited, baseline: Self.charge.definition, disk: pulled)
        #expect(tab.tab.definition == edited)
        #expect(tab.tab.baseline == pulled)
        #expect(tab.tab.isChangedOnDisk)
    }

    @Test func `the Request is gone: the Tab comes back as a Draft with its content`() throws {
        let tab = try relaunch(definition: edited, baseline: Self.charge.definition, disk: nil)
        #expect(tab.tab.source == .draft)
        #expect(tab.tab.definition == edited)
        #expect(tab.tab.baseline == nil)
    }
}

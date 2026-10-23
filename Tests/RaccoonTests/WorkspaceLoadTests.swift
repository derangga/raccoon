import Foundation
@testable import Raccoon
import RaccoonData
import RaccoonDomain
import RaccoonTesting
import Testing

/// Loading one Data Folder as a Workspace: raccoon.json, the SecretStore built for its id, and
/// the Session restored only when the folder could be scanned.
@MainActor
struct WorkspaceLoadTests {
    let temp = FileManager.default.temporaryDirectory.appending(path: "raccoon-\(UUID())")
    let watch = ManualFolderWatch()
    /// The id each SecretStore was built for, nil when the Workspace has none.
    let secretIDs = IDLog()

    final class IDLog {
        var ids: [WorkspaceID?] = []
    }

    func makeWindow(root: URL, workspaces: [String] = []) -> WindowModel {
        let log = secretIDs
        return WindowModel(
            dataFolder: DataFolderLocation(
                root: root.path, workspaces: workspaces, open: { DiskDataFolderStore(root: URL(filePath: $0)) }, remember: { _ in }),
            folderWatch: watch, sessionStore: { [temp] in DiskSessionStore(directory: temp.appending(path: "Support"), root: $0) },
            secrets: { id in
                log.ids.append(id)
                return InMemorySecretStore()
            },
            instants: FixedInstantSource(.now),
            makeTab: { _ in
                TabModel(transport: ScriptedTransport(.failure(.timedOut)), secrets: InMemorySecretStore(), files: DictionaryFileReading([:]),
                         instants: FixedInstantSource(.now), clipboard: RecordingClipboardWriter())
            }
        )
    }

    func session(for root: URL) -> DiskSessionStore {
        DiskSessionStore(directory: temp.appending(path: "Support"), root: root.path)
    }

    func draft(_ url: String) -> TabSnapshot {
        var definition = RequestDefinition.empty
        definition.url = url
        return TabSnapshot(id: TabID(UUID()), source: .draft, definition: definition, baseline: nil)
    }

    @Test func `a folder with no raccoon.json gets one, and the watch event for it is dropped`() async throws {
        let root = temp.appending(path: "api")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let window = makeWindow(root: root, workspaces: [root.path])

        window.loadDataFolder()

        let bytes = try Data(contentsOf: root.appending(path: "raccoon.json"))
        let id = try WorkspaceFile.decode(bytes)
        #expect(secretIDs.ids.last == id)
        #expect(window.dataFolderError == nil)
        let before = window.scanCount
        watch.emit(["raccoon.json"])
        await Task.yield()
        await Task.yield()
        #expect(window.scanCount == before)
    }

    @Test func `a folder with a raccoon.json keeps it byte for byte and builds secrets for its id`() throws {
        let root = temp.appending(path: "api")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let id = WorkspaceID(UUID())
        let bytes = WorkspaceFile.encode(id)
        try bytes.write(to: root.appending(path: "raccoon.json"))
        let window = makeWindow(root: root, workspaces: [root.path])

        window.loadDataFolder()

        #expect(secretIDs.ids.last == id)
        #expect(try Data(contentsOf: root.appending(path: "raccoon.json")) == bytes)
    }

    @Test func `an undecodable raccoon.json is not rewritten and its Workspace has no id`() throws {
        let root = temp.appending(path: "api")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let broken = Data("{ not json".utf8)
        try broken.write(to: root.appending(path: "raccoon.json"))
        let window = makeWindow(root: root, workspaces: [root.path])

        window.loadDataFolder()

        #expect(try Data(contentsOf: root.appending(path: "raccoon.json")) == broken)
        #expect(secretIDs.ids.last == .some(nil))
        #expect(window.dataFolderError == nil)
    }

    @Test func `a remembered root that is missing shows the banner, creates nothing and leaves its Session alone`() throws {
        let root = temp.appending(path: "gone")
        let store = session(for: root)
        let drafts = [draft("https://a.example"), draft("https://b.example")]
        let saved = SessionFile.encode(Session(tabs: drafts, selected: drafts[0].id, activeEnvironment: nil))
        try store.write(saved)
        let window = makeWindow(root: root, workspaces: [root.path])

        window.loadDataFolder()
        window.newTab()
        window.quit()

        guard case .unreadable = window.dataFolderError else { Issue.record("no banner: \(String(describing: window.dataFolderError))"); return }
        #expect(!FileManager.default.fileExists(atPath: root.path))
        #expect(try store.read() == saved)
        #expect(window.tabs.count == 2)
        #expect(window.tabs[0].tab.definition == .empty)
    }

    @Test func `the first launch creates the root and lists it`() throws {
        let root = temp.appending(path: "Raccoon")
        var listed: [[String]] = []
        let window = WindowModel(
            dataFolder: DataFolderLocation(
                root: root.path, open: { DiskDataFolderStore(root: URL(filePath: $0)) }, remember: { _ in },
                rememberWorkspaces: { listed.append($0) }),
            folderWatch: watch, sessionStore: { [temp] in DiskSessionStore(directory: temp.appending(path: "Support"), root: $0) },
            secrets: { _ in InMemorySecretStore() }, instants: FixedInstantSource(.now),
            makeTab: { _ in
                TabModel(transport: ScriptedTransport(.failure(.timedOut)), secrets: InMemorySecretStore(), files: DictionaryFileReading([:]),
                         instants: FixedInstantSource(.now), clipboard: RecordingClipboardWriter())
            }
        )

        window.loadDataFolder()

        #expect(FileManager.default.fileExists(atPath: root.appending(path: "raccoon.json").path))
        #expect(window.workspaces == [root.path])
        #expect(listed == [[root.path]])
    }

    @Test func `a folder that reads but cannot be written still restores its Session`() throws {
        let root = temp.appending(path: "ReadOnly")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let drafts = [draft("https://a.example"), draft("https://b.example")]
        try session(for: root).write(SessionFile.encode(Session(tabs: drafts, selected: drafts[1].id, activeEnvironment: nil)))
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: root.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: root.path) }
        let window = makeWindow(root: root, workspaces: [root.path])

        window.loadDataFolder()

        guard case .unwritable = window.dataFolderError else { Issue.record("no banner: \(String(describing: window.dataFolderError))"); return }
        #expect(secretIDs.ids.last == .some(nil))
        #expect(window.tabs.map(\.tab.snapshot) == drafts)
        #expect(window.selected == drafts[1].id)
    }
}

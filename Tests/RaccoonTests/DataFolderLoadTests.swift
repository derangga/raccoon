import Foundation
@testable import Raccoon
import RaccoonData
import RaccoonDomain
import RaccoonTesting
import Testing

/// Loading the Data Folder over a live store in a temp dir, with a manual FolderWatch.
@MainActor
struct DataFolderLoadTests {
    let temp = FileManager.default.temporaryDirectory.appending(path: "raccoon-\(UUID())")
    let watch = ManualFolderWatch()
    let transport = ScriptedTransport(.success(Response(status: 200, headers: [], body: Data(), elapsed: .zero, byteCount: 0)))

    func makeWindow(root: URL, remembered: @escaping (String) -> Void = { _ in }) -> WindowModel {
        WindowModel(
            dataFolder: DataFolderLocation(root: root.path, open: { DiskDataFolderStore(root: URL(filePath: $0)) }, remember: remembered),
            folderWatch: watch, sessionStore: DiskSessionStore(directory: temp.appending(path: "Support"), root: root.path),
            secrets: InMemorySecretStore(), instants: FixedInstantSource(.now),
            makeTab: { [transport] in
                TabModel(transport: transport, secrets: InMemorySecretStore(), files: DictionaryFileReading([:]),
                         instants: FixedInstantSource(.now), clipboard: RecordingClipboardWriter())
            }
        )
    }

    func put(_ request: Request, at path: String, in root: URL) throws {
        let url = root.appending(path: path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try RequestFile.encode(request).write(to: url)
    }

    static let charge = Request(id: RequestID(UUID()), name: "Create charge", definition: .empty)

    @Test func `the index matches the files, and the watch starts on the root`() throws {
        let root = temp.appending(path: "Raccoon")
        try put(Self.charge, at: "Payments API/Create charge.json", in: root)

        let window = makeWindow(root: root)
        window.loadDataFolder()

        #expect(window.index.collections == [
            Collection(name: "Payments API", nodes: [.request(Self.charge.id, name: "Create charge", method: "GET", path: "Payments API/Create charge.json")]),
        ])
        #expect(window.index.path(of: Self.charge.id) == "Payments API/Create charge.json")
        #expect(window.dataFolderError == nil)
        #expect(watch.log == ["start \(root.path)"])
    }

    @Test func `opening a Workspace ends the old watch before the new one starts, and remembers it`() async throws {
        let (a, b) = (temp.appending(path: "A"), temp.appending(path: "B"))
        try put(Self.charge, at: "In B/Create charge.json", in: b)
        var remembered: [String] = []
        let window = makeWindow(root: a) { remembered.append($0) }
        window.loadDataFolder()

        await window.openWorkspace(b.path)

        #expect(watch.log == ["start \(a.path)", "end \(a.path)", "start \(b.path)"])
        #expect(window.index.collections.map(\.name) == ["In B"])
        #expect(remembered == [b.path])
    }

    @Test func `a root that is not writable shows the banner state, and a Draft still sends`() async throws {
        let root = temp.appending(path: "ReadOnly")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: root.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: root.path) }

        let window = makeWindow(root: root)
        window.loadDataFolder()

        guard case .unwritable(let path, _) = window.dataFolderError else { Issue.record("no banner state"); return }
        #expect(path == root.path)
        #expect(window.index.collections.isEmpty)

        let draft = try #require(window.selectedTab)
        draft.typeInURLBar("https://example.com")
        draft.send()
        await draft.inFlight?.value
        #expect(transport.requests.count == 1)
        guard case .received = draft.tab.response else { Issue.record("not received: \(draft.tab.response)"); return }
    }

    @Test func `a file added on disk shows after the watch reports it`() async throws {
        let root = temp.appending(path: "Raccoon")
        try FileManager.default.createDirectory(at: root.appending(path: "Payments API"), withIntermediateDirectories: true)
        let window = makeWindow(root: root)
        window.loadDataFolder()

        try put(Self.charge, at: "Payments API/Create charge.json", in: root)
        watch.emit(["Payments API/Create charge.json"])
        for _ in 0..<100 where window.index.path(of: Self.charge.id) == nil { await Task.yield() }

        #expect(window.index.path(of: Self.charge.id) == "Payments API/Create charge.json")
    }
}

import AppKit
@testable import Raccoon
import RaccoonData
import RaccoonDomain
import RaccoonTesting
import Testing

/// Files changed under open Tabs, with a manual FolderWatch over a live store in a temp dir.
@MainActor
struct FilesChangedTests {
    let temp = FileManager.default.temporaryDirectory.appending(path: "raccoon-\(UUID())")
    let watch = ManualFolderWatch()
    var root: URL { temp.appending(path: "Raccoon") }
    let path = "Payments API/Create charge.json"
    var file: URL { root.appending(path: path) }

    func makeWindow() -> WindowModel {
        WindowModel(
            dataFolder: .test(root), folderWatch: watch,
            sessionStore: DiskSessionStore(directory: temp.appending(path: "Support"), root: root.path), secrets: InMemorySecretStore(),
            instants: FixedInstantSource(.now),
            makeTab: {
                TabModel(transport: ScriptedTransport(.failure(.timedOut)), secrets: InMemorySecretStore(), files: DictionaryFileReading([:]),
                         instants: FixedInstantSource(.now), clipboard: RecordingClipboardWriter())
            }
        )
    }

    func open() throws -> (WindowModel, TabModel) {
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try RequestFile.encode(OpenRequestTests.charge).write(to: file)
        let window = makeWindow()
        window.loadDataFolder()
        window.openRequest(OpenRequestTests.charge.id)
        return (window, try #require(window.selectedTab))
    }

    /// What `git pull` would leave: the same Request with a changed URL, written by someone else.
    var pulled: RequestDefinition {
        var definition = OpenRequestTests.charge.definition
        definition.url = "https://api.example.com/v2/charges"
        return definition
    }

    func writeOnDisk(_ definition: RequestDefinition) throws {
        try RequestFile.encode(Request(id: OpenRequestTests.charge.id, name: "Create charge", definition: definition)).write(to: file)
    }

    func deliver(_ paths: [String], to window: WindowModel) async {
        let before = window.scanCount
        watch.emit(paths)
        for _ in 0..<200 where window.scanCount == before { await Task.yield() }
    }

    @Test func `a clean Tab reloads silently`() async throws {
        let (window, tab) = try open()
        try writeOnDisk(pulled)

        await deliver([path], to: window)

        #expect(tab.tab.definition == pulled)
        #expect(tab.tab.baseline == pulled)
        #expect(!tab.tab.isChangedOnDisk)
        #expect(tab.notice == nil)
    }

    @Test func `a Dirty Tab keeps its edits and is Changed on Disk; Reload takes the file`() async throws {
        let (window, tab) = try open()
        tab.tab.definition.headers.append(Row(name: "X-Mine", value: "1"))
        let mine = tab.tab.definition
        try writeOnDisk(pulled)

        await deliver([path], to: window)

        #expect(tab.tab.definition == mine)
        #expect(tab.tab.baseline == pulled)
        #expect(tab.tab.isChangedOnDisk)

        window.reload(tab.tab.id)
        #expect(tab.tab.definition == pulled)
        #expect(!tab.tab.isChangedOnDisk)
        #expect(!tab.tab.isDirty)
    }

    @Test func `Keep Mine keeps the edits against the new file, and ⌘S writes over it`() async throws {
        let (window, tab) = try open()
        tab.tab.definition.headers.append(Row(name: "X-Mine", value: "1"))
        let mine = tab.tab.definition
        try writeOnDisk(pulled)
        await deliver([path], to: window)

        window.keepMine(tab.tab.id)
        #expect(!tab.tab.isChangedOnDisk)
        #expect(tab.tab.isDirty)
        #expect(tab.tab.baseline == pulled)

        window.save(tab.tab.id)
        #expect(try RequestFile.decode(Data(contentsOf: file)).definition == mine)
    }

    @Test func `a deleted file turns its Tab into a Draft with its content`() async throws {
        let (window, tab) = try open()
        tab.tab.definition.headers.append(Row(name: "X-Mine", value: "1"))
        let mine = tab.tab.definition
        try FileManager.default.removeItem(at: file)

        await deliver([path], to: window)

        #expect(tab.tab.source == .draft)
        #expect(tab.tab.definition == mine)
        #expect(tab.tab.baseline == nil)
        #expect(tab.notice == .deletedOnDisk(file: "Create charge.json"))
    }

    @Test func `our own save reported by the watch causes no rescan`() async throws {
        let (window, tab) = try open()
        tab.tab.definition.headers.append(Row(name: "X-Mine", value: "1"))
        window.save(tab.tab.id)
        let before = window.scanCount

        watch.emit([path])
        for _ in 0..<50 { await Task.yield() }

        #expect(window.scanCount == before)
        #expect(!tab.tab.isChangedOnDisk)
    }

    @Test func `a renamed Request renames its Tab and changes nothing else`() async throws {
        let (window, tab) = try open()
        try RequestFile.encode(Request(id: OpenRequestTests.charge.id, name: "Charge a card", definition: OpenRequestTests.charge.definition))
            .write(to: file)

        await deliver([path], to: window)

        #expect(window.name(of: tab.tab) == "Charge a card")
        #expect(!tab.tab.isDirty)
        #expect(!tab.tab.isChangedOnDisk)
    }

    @Test func `a file broken under its Tab is never written over`() async throws {
        let (window, tab) = try open()
        tab.tab.definition.headers.append(Row(name: "X-Mine", value: "1"))
        try Data("{ broken".utf8).write(to: file)
        await deliver([path], to: window)
        #expect(tab.tab.source == .request(OpenRequestTests.charge.id))

        window.save(tab.tab.id)

        #expect(try Data(contentsOf: file) == Data("{ broken".utf8))
        #expect(tab.notice == .notSaved(file: "Create charge.json", reason: "it can't be read, and Raccoon won't change it"))
        #expect(tab.tab.isDirty)
    }

    @Test func `a batch of 200 paths is one rescan`() async throws {
        let (window, _) = try open()
        let paths = (0..<200).map { "Payments API/R\($0).json" }
        for path in paths {
            try RequestFile.encode(Request(id: RequestID(UUID()), name: path, definition: .empty)).write(to: root.appending(path: path))
        }
        let before = window.scanCount

        await deliver(paths, to: window)
        for _ in 0..<50 { await Task.yield() }

        #expect(window.scanCount == before + 1)
        #expect(window.index.collections[0].nodes.count == 201)
    }

    @Test func `the Changed on Disk banner's Keep Mine and Reload act; it has no Dismiss`() async throws {
        let (window, tab) = try open()
        tab.tab.definition.headers.append(Row(name: "X-Mine", value: "1"))
        try writeOnDisk(pulled)
        await deliver([path], to: window)
        let binding = TabBannerBinding(window: window, theme: ThemeEnvironment(catalog: ThemeCatalog.load(), isDark: false), reduceMotion: { true })
        #expect(binding.view.content?.buttons.map(\.title) == ["Keep Mine", "Reload"])

        binding.view.onButton?(1)
        #expect(tab.tab.definition == pulled)
        #expect(!tab.tab.isChangedOnDisk)
    }
}

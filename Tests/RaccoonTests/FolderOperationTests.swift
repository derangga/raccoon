import AppKit
@testable import Raccoon
import RaccoonData
import RaccoonDomain
import RaccoonTesting
import Testing

/// New Collection, New Folder, rename, move and Move to Trash, over a live store in a temp dir.
@MainActor
struct FolderOperationTests {
    let temp = FileManager.default.temporaryDirectory.appending(path: "raccoon-\(UUID())")
    let watch = ManualFolderWatch()
    var root: URL { temp.appending(path: "Raccoon") }
    static let charge = OpenRequestTests.charge
    let chargePath = "Payments API/Refunds/Create charge.json"

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

    func exists(_ path: String) -> Bool { FileManager.default.fileExists(atPath: root.appending(path: path).path) }

    /// Payments API/Refunds/Create charge.json open in a Tab, and an empty Collection "Orders".
    func setUp() throws -> (WindowModel, TabModel) {
        let url = root.appending(path: chargePath)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.appending(path: "Orders"), withIntermediateDirectories: true)
        try RequestFile.encode(Self.charge).write(to: url)
        let window = makeWindow()
        window.loadDataFolder()
        window.openRequest(Self.charge.id)
        return (window, try #require(window.selectedTab))
    }

    /// Delivers what FSEvents would report and lets the window handle it.
    func echo(_ paths: [String]) async {
        watch.emit(paths)
        for _ in 0..<50 { await Task.yield() }
    }

    @Test func `New Collection shows at once, and the watch echo is ours`() async throws {
        let (window, _) = try setUp()
        let scans = window.scanCount

        try window.newCollection("Health")
        await echo(["Health"])

        #expect(exists("Health"))
        #expect(window.index.collections.map(\.name) == ["Health", "Orders", "Payments API"])
        #expect(window.scanCount == scans)
    }

    @Test func `New Folder goes in its parent, and a taken name gets 2`() throws {
        let (window, _) = try setUp()

        try window.newFolder("Webhooks", in: "Payments API")
        try window.newFolder("webhooks", in: "Payments API")

        #expect(exists("Payments API/Webhooks"))
        #expect(exists("Payments API/webhooks 2"))
        #expect(window.index.folders.contains("Payments API/webhooks 2"))
    }

    @Test func `renaming a Folder keeps its open Tab on the same Request`() async throws {
        let (window, tab) = try setUp()
        tab.tab.definition.headers.append(Row(name: "X-Mine", value: "1"))
        let scans = window.scanCount

        try window.rename("Payments API/Refunds", to: "Charges")
        await echo(["Payments API/Refunds", "Payments API/Charges", chargePath, "Payments API/Charges/Create charge.json"])

        #expect(exists("Payments API/Charges/Create charge.json"))
        #expect(window.index.path(of: Self.charge.id) == "Payments API/Charges/Create charge.json")
        #expect(tab.tab.source == .request(Self.charge.id))
        #expect(tab.tab.isDirty)
        #expect(!tab.tab.isChangedOnDisk)
        #expect(window.scanCount == scans)
    }

    @Test func `renaming a Request renames it inside and its file, and its Tab follows`() throws {
        let (window, tab) = try setUp()

        try window.rename(chargePath, to: "Charge a card")

        let path = "Payments API/Refunds/Charge a card.json"
        #expect(!exists(chargePath))
        #expect(try RequestFile.decode(Data(contentsOf: root.appending(path: path))) == Request(id: Self.charge.id, name: "Charge a card", definition: Self.charge.definition))
        #expect(window.name(of: tab.tab) == "Charge a card")
        #expect(!tab.tab.isDirty)
    }

    @Test func `moving a Request to another Collection: the Tab follows`() throws {
        let (window, tab) = try setUp()

        try window.move(chargePath, to: "Orders")

        #expect(exists("Orders/Create charge.json"))
        #expect(window.index.path(of: Self.charge.id) == "Orders/Create charge.json")
        #expect(tab.tab.source == .request(Self.charge.id))
    }

    @Test func `Move to Trash takes the file away and its open Tab becomes a Draft`() async throws {
        let (window, tab) = try setUp()
        let scans = window.scanCount

        try window.trash(chargePath)
        await echo([chargePath])

        #expect(!exists(chargePath))
        #expect(tab.tab.source == .draft)
        #expect(tab.tab.definition == Self.charge.definition)
        #expect(tab.notice == .deletedOnDisk(file: "Create charge.json"))
        #expect(window.index.path(of: Self.charge.id) == nil)
        #expect(window.scanCount == scans)
    }

    @Test func `a rename that fails changes nothing`() throws {
        let (window, _) = try setUp()
        let parent = root.appending(path: "Payments API")
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: parent.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: parent.path) }
        let before = window.index

        #expect(throws: StoreError.self) { try window.rename("Payments API/Refunds", to: "Charges") }
        #expect(window.index == before)
    }
}

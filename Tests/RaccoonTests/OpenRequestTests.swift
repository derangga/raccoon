import AppKit
@testable import Raccoon
import RaccoonData
import RaccoonDomain
import RaccoonTesting
import Testing

/// openRequest over a live store in a temp dir.
@MainActor
struct OpenRequestTests {
    let temp = FileManager.default.temporaryDirectory.appending(path: "raccoon-\(UUID())")
    var root: URL { temp.appending(path: "Raccoon") }

    func makeWindow() -> WindowModel {
        WindowModel(
            dataFolder: .test(root), folderWatch: ManualFolderWatch(),
            sessionStore: DiskSessionStore(directory: temp.appending(path: "Support")), secrets: InMemorySecretStore(),
            instants: FixedInstantSource(.now),
            makeTab: {
                TabModel(transport: ScriptedTransport(.failure(.timedOut)), secrets: InMemorySecretStore(), files: DictionaryFileReading([:]),
                         instants: FixedInstantSource(.now), clipboard: RecordingClipboardWriter())
            }
        )
    }

    static var charge: Request {
        var definition = RequestDefinition.empty
        definition.method = "POST"
        definition.url = "https://api.example.com/charges"
        definition.headers = [Row(name: "Idempotency-Key", value: "{{key}}")]
        return Request(id: RequestID(UUID(uuidString: "00000000-0000-4000-8000-0000000000C1")!), name: "Create charge", definition: definition)
    }

    func put(_ request: Request, at path: String) throws {
        let url = root.appending(path: path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try RequestFile.encode(request).write(to: url)
    }

    @Test func `opening a Request adds a clean Tab for it after the selected one, selected`() throws {
        try put(Self.charge, at: "Payments API/Create charge.json")
        let window = makeWindow()
        window.loadDataFolder()
        let draft = window.tabs[0].tab.id

        window.openRequest(Self.charge.id)

        #expect(window.tabs.count == 2)
        let tab = window.tabs[1].tab
        #expect(tab.source == .request(Self.charge.id))
        #expect(tab.definition == Self.charge.definition)
        #expect(tab.baseline == Self.charge.definition)
        #expect(!tab.isDirty)
        #expect(window.selected == tab.id)
        #expect(window.tabs[0].tab.id == draft)
    }

    @Test func `opening the same Request twice leaves one Tab and selects it`() throws {
        try put(Self.charge, at: "Payments API/Create charge.json")
        let window = makeWindow()
        window.loadDataFolder()
        window.openRequest(Self.charge.id)
        let opened = try #require(window.selected)
        window.select(window.tabs[0].tab.id)

        window.openRequest(Self.charge.id)

        #expect(window.tabs.count == 2)
        #expect(window.selected == opened)
    }

    @Test func `a file that broke since the scan opens no Tab and its row turns unreadable`() throws {
        try put(Self.charge, at: "Payments API/Create charge.json")
        let window = makeWindow()
        window.loadDataFolder()
        try Data("{ broken".utf8).write(to: root.appending(path: "Payments API/Create charge.json"))

        window.openRequest(Self.charge.id)

        #expect(window.tabs.count == 1)
        #expect(window.index.collections[0].nodes == [
            .unreadable(path: "Payments API/Create charge.json", reason: "Not valid JSON at line 1. Raccoon won't change this file."),
        ])
    }

    @Test func `a Request Tab is named after its Request; a Draft after its URL`() throws {
        try put(Self.charge, at: "Payments API/Create charge.json")
        let window = makeWindow()
        window.loadDataFolder()
        window.openRequest(Self.charge.id)

        #expect(window.name(of: window.tabs[1].tab) == "Create charge")
        window.tabs[0].tab.definition.url = "https://api.example.com/v1/refunds?x=1"
        #expect(window.name(of: window.tabs[0].tab) == "/v1/refunds")
    }

    @Test func `the tab strip shows the Request's name`() throws {
        try put(Self.charge, at: "Payments API/Create charge.json")
        let window = makeWindow()
        window.loadDataFolder()
        window.openRequest(Self.charge.id)
        let strip = TabStripView(window: window, theme: ThemeEnvironment(catalog: ThemeCatalog.load(), isDark: false))
        strip.frame = NSRect(x: 0, y: 0, width: 1_000, height: TabStripView.height)
        strip.layoutSubtreeIfNeeded()

        #expect(strip.items[1].name.stringValue == "Create charge")
        #expect(strip.items[1].toolTip == "Create charge")
    }

    @Test func `clicking a Request row in the sidebar opens it`() throws {
        try put(Self.charge, at: "Payments API/Create charge.json")
        let window = makeWindow()
        window.loadDataFolder()
        let sidebar = SidebarViewController(window: window, theme: ThemeEnvironment(catalog: ThemeCatalog.load(), isDark: false), reveal: { _ in })
        sidebar.view.frame = NSRect(x: 0, y: 0, width: 232, height: 600)
        sidebar.outline.expandItem(nil, expandChildren: true)

        sidebar.open(row: 1)

        #expect(window.selectedTab?.tab.source == .request(Self.charge.id))
    }

    @Test func `two Tabs for one Request is a bug, and relaunch dies on it`() async {
        await #expect(processExitsWith: .failure) {
            await MainActor.run {
                let temp = FileManager.default.temporaryDirectory.appending(path: "raccoon-\(UUID())")
                let store = DiskSessionStore(directory: temp)
                let id = RequestID(UUID())
                let tabs = (0..<2).map { _ in TabSnapshot(id: TabID(UUID()), source: .request(id), definition: .empty, baseline: .empty) }
                try! store.write(SessionFile.encode(Session(tabs: tabs, selected: nil, activeEnvironment: nil)))
                let window = WindowModel(
                    dataFolder: .test(temp.appending(path: "Raccoon")), folderWatch: ManualFolderWatch(), sessionStore: store,
                    secrets: InMemorySecretStore(), instants: FixedInstantSource(.now),
                    makeTab: {
                        TabModel(transport: ScriptedTransport(.failure(.timedOut)), secrets: InMemorySecretStore(), files: DictionaryFileReading([:]),
                                 instants: FixedInstantSource(.now), clipboard: RecordingClipboardWriter())
                    }
                )
                window.relaunch()
            }
        }
    }
}

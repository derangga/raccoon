import AppKit
@testable import Raccoon
import RaccoonData
import RaccoonDomain
import RaccoonTesting
import Testing

/// ⌘S on a Request Tab, over a live store in a temp dir.
@MainActor
struct SaveRequestTests {
    let temp = FileManager.default.temporaryDirectory.appending(path: "raccoon-\(UUID())")
    let watch = ManualFolderWatch()
    var root: URL { temp.appending(path: "Raccoon") }
    var file: URL { root.appending(path: "Payments API/Create charge.json") }
    let theme = ThemeEnvironment(catalog: ThemeCatalog.load(), isDark: false)

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

    /// A window with Create charge open and edited, so the Tab is Dirty.
    func openEdited() throws -> (WindowModel, TabModel) {
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try RequestFile.encode(OpenRequestTests.charge).write(to: file)
        let window = makeWindow()
        window.loadDataFolder()
        window.openRequest(OpenRequestTests.charge.id)
        let tab = try #require(window.selectedTab)
        tab.tab.definition.headers.append(Row(name: "X-Debug", value: "1"))
        #expect(tab.tab.isDirty)
        return (window, tab)
    }

    @Test func `saving writes the file, clears Dirty and records the write as ours`() throws {
        let (window, tab) = try openEdited()

        window.save(tab.tab.id)

        let written = try Data(contentsOf: file)
        #expect(try RequestFile.decode(written) == Request(id: OpenRequestTests.charge.id, name: "Create charge", definition: tab.tab.definition))
        #expect(!tab.tab.isDirty)
        #expect(tab.tab.baseline == tab.tab.definition)
        #expect(window.ledger.isOurs("Payments API/Create charge.json", written))
    }

    @Test func `a save that changes nothing writes the same bytes`() throws {
        let (window, tab) = try openEdited()
        tab.tab.definition = OpenRequestTests.charge.definition
        let before = try Data(contentsOf: file)

        window.save(tab.tab.id)

        #expect(try Data(contentsOf: file) == before)
    }

    @Test func `our own save reported by the watch is not Changed on Disk`() async throws {
        let (window, tab) = try openEdited()
        window.save(tab.tab.id)

        watch.emit(["Payments API/Create charge.json"])
        for _ in 0..<20 { await Task.yield() }

        #expect(!tab.tab.isChangedOnDisk)
        #expect(!tab.tab.isDirty)
    }

    @Test func `a write that fails shows Not saved and the Tab stays Dirty`() throws {
        let (window, tab) = try openEdited()
        let folder = file.deletingLastPathComponent()
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: folder.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: folder.path) }
        let before = try Data(contentsOf: file)

        window.save(tab.tab.id)

        guard case .notSaved(let name, let reason) = tab.notice else { Issue.record("no notice: \(String(describing: tab.notice))"); return }
        #expect(name == "Create charge.json")
        #expect(!reason.isEmpty)
        #expect(tab.tab.isDirty)
        #expect(try Data(contentsOf: file) == before)
    }

    @Test func `the Tab banners read as board 05 and 09`() {
        #expect(TabBanner.content(notice: .notSaved(file: "Update charge.json", reason: "permission denied"), changedOnDisk: nil) == Banner(
            glyph: .error, lead: "Not saved.",
            detail: [.text(" Couldn't write Update charge.json: permission denied. The Tab keeps your edits.")],
            buttons: [Banner.Button(title: "Dismiss", isPrimary: false)]))
        #expect(TabBanner.content(notice: .deletedOnDisk(file: "Update charge.json"), changedOnDisk: nil) == Banner(
            glyph: .warning, lead: "Deleted on disk.",
            detail: [.text(" Update charge.json is gone. This Tab is now a Draft with your content, and ⌘S saves it again.")],
            buttons: [Banner.Button(title: "Dismiss", isPrimary: false)]))
        #expect(TabBanner.content(notice: nil, changedOnDisk: "Create charge.json") == Banner(
            glyph: .warning, lead: "Changed on Disk.",
            detail: [.text(" Create charge.json was changed outside Raccoon. Your edits are kept until you choose.")],
            buttons: [Banner.Button(title: "Keep Mine", isPrimary: false), Banner.Button(title: "Reload", isPrimary: true)]))
        #expect(TabBanner.content(notice: nil, changedOnDisk: nil) == nil)
    }

    func settle() async {
        for _ in 0..<10 { await Task.yield() }
    }

    @Test func `the banner sits between the tab strip and the URL bar and follows the selected Tab`() async throws {
        let (window, tab) = try openEdited()
        let folder = file.deletingLastPathComponent()
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: folder.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: folder.path) }
        let strip = TabStripView(window: window, theme: theme)
        let content = ContentViewController(strip: strip, breadcrumb: BreadcrumbBinding(window: window, theme: theme, select: { _ in }),
                                            tab: TabViewController(model: tab, theme: theme),
                                            banner: TabBannerBinding(window: window, theme: theme, reduceMotion: { true }),
                                            emptyState: EmptyStateView(theme: theme, menu: nil))
        content.view.frame = NSRect(x: 0, y: 0, width: 900, height: 600)

        window.save(tab.tab.id)
        await settle()
        content.view.layoutSubtreeIfNeeded()
        let banner = content.banner.view
        #expect(!banner.isHidden)
        #expect(banner.content?.lead == "Not saved.")
        #expect(banner.frame.maxY == content.breadcrumb.bar.frame.minY)
        #expect(banner.frame.minY == content.tab.view.frame.maxY)

        window.select(window.tabs[0].tab.id)
        await settle()
        #expect(banner.content == nil)
        window.select(tab.tab.id)
        await settle()
        #expect(banner.content?.lead == "Not saved.")

        banner.onButton?(0)
        await settle()
        #expect(tab.notice == nil)
        #expect(banner.content == nil)
    }

    @Test func `File ▸ Save is ⌘S`() throws {
        let file = try #require(MainMenu.make(theme: ThemeController(defaults: .standard, catalog: ThemeCatalog.load(), appearanceSource: NSView()))
            .item(withTitle: "File")?.submenu)
        let save = try #require(file.item(withTitle: "Save"))
        #expect(save.keyEquivalent == "s")
        #expect(save.keyEquivalentModifierMask == .command)
        #expect(save.action == #selector(AppDelegate.save(_:)))
    }
}

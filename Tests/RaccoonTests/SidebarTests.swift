import AppKit
@testable import Raccoon
import RaccoonData
import RaccoonDomain
import RaccoonTesting
import Testing

@MainActor
struct SidebarTests {
    let theme = ThemeEnvironment(catalog: ThemeCatalog.load(), isDark: false)
    let watch = ManualFolderWatch()
    let temp = FileManager.default.temporaryDirectory.appending(path: "raccoon-\(UUID())")
    var root: URL { temp.appending(path: "Raccoon") }

    func makeWindow() -> WindowModel {
        WindowModel(
            dataFolder: .test(root), folderWatch: watch,
            sessionStore: DiskSessionStore(directory: temp.appending(path: "Support")), secrets: InMemorySecretStore(),
            instants: FixedInstantSource(.now),
            makeTab: {
                TabModel(transport: ScriptedTransport(.failure(.timedOut)), secrets: InMemorySecretStore(), files: DictionaryFileReading([:]),
                         instants: FixedInstantSource(.now), clipboard: RecordingClipboardWriter())
            }
        )
    }

    func put(_ name: String, method: String = "GET", at path: String) throws {
        var definition = RequestDefinition.empty
        definition.method = method
        try write(RequestFile.encode(Request(id: RequestID(UUID()), name: name, definition: definition)), at: path)
    }

    func write(_ data: Data, at path: String) throws {
        let url = root.appending(path: path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url)
    }

    /// A sidebar 232 pt wide over a loaded window, every row expanded.
    func sidebar(_ window: WindowModel, reveal: @escaping (String) -> Void = { _ in }) -> SidebarViewController {
        window.loadDataFolder()
        let sidebar = SidebarViewController(window: window, theme: theme, reveal: reveal)
        sidebar.view.frame = NSRect(x: 0, y: 0, width: 232, height: 700)
        sidebar.outline.expandItem(nil, expandChildren: true)
        sidebar.view.layoutSubtreeIfNeeded()
        return sidebar
    }

    func cell<T: NSView>(_ sidebar: SidebarViewController, row: Int, as type: T.Type = T.self) throws -> T {
        try #require(sidebar.outline.view(atColumn: 0, row: row, makeIfNecessary: true) as? T)
    }

    @Test func `Collections, Folders and Requests in order, 24 pt rows, 16 pt indent per level`() throws {
        try put("List charges", at: "Payments API/List charges.json")
        try put("List refunds", at: "Payments API/Refunds/List refunds.json")
        try FileManager.default.createDirectory(at: root.appending(path: "Auth Service"), withIntermediateDirectories: true)
        let sidebar = sidebar(makeWindow())
        let outline = sidebar.outline

        let rows = (0..<outline.numberOfRows).map { (outline.level(forRow: $0), (outline.item(atRow: $0) as? SidebarItem)?.name ?? "") }
        #expect(rows.map(\.1) == ["Auth Service", "Payments API", "Refunds", "List refunds", "List charges"])
        #expect(rows.map(\.0) == [0, 0, 1, 2, 1])
        #expect(outline.indentationPerLevel == 16)
        #expect(outline.rect(ofRow: 4).height == 24)
        #expect(sidebar.sectionLabel.stringValue == "Collections")
    }

    @Test(arguments: ["GET", "DELETE", "OPTIONS", "PROPFIND"])
    func `the badge is 52 pt, right-aligned, and fits the method`(method: String) throws {
        try put("R", method: method, at: "C/R.json")
        let sidebar = sidebar(makeWindow())
        let row: RequestCell = try cell(sidebar, row: 1)
        // A label keeps 2 pt of padding each side: its text area is the 52 pt badge.
        #expect(row.badge.frame.width - 4 == 52)
        // The drawn alignment: an attributed string's paragraph style overrides the field's.
        let style = row.badge.attributedStringValue.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle
        #expect(style?.alignment == .right)
        #expect(row.badge.stringValue == method)
        #expect((row.badge.cell?.cellSize.width ?? .infinity) <= row.badge.frame.width)
        #expect(row.badge.textColor == theme.color(.method(method)))
    }

    @Test func `a longer method end-truncates in the badge`() throws {
        try put("R", method: "VERSION-CONTROL", at: "C/R.json")
        let row: RequestCell = try cell(sidebar(makeWindow()), row: 1)
        #expect(row.badge.frame.width - 4 == 52)
        #expect(row.badge.lineBreakMode == .byTruncatingTail)
    }

    @Test func `break-ui: a long unreadable file name keeps the Reveal button and its reason line`() throws {
        try write(Data(#"{"version": 3}"#.utf8), at: "Payments API/Create charge (conflicted copy 2026-10-14).json")
        let sidebar = sidebar(makeWindow())
        let row: UnreadableCell = try cell(sidebar, row: 1)
        let rowRect = sidebar.outline.rect(ofRow: 1)

        #expect(row.name.stringValue == "Create charge (conflicted copy 2026-10-14).json")
        #expect(row.reason.stringValue == "Unknown file version 3.")
        #expect(row.glyph.contentTintColor == theme.color(.warning))
        #expect(row.reveal.frame.size == NSSize(width: 20, height: 18))
        #expect(row.reveal.toolTip == "Reveal in Finder")
        #expect(row.reveal.accessibilityLabel() == "Reveal in Finder")
        let reveal = row.convert(row.reveal.frame, to: sidebar.outline)
        #expect(reveal.maxX <= sidebar.outline.bounds.maxX)
        #expect(row.name.frame.maxX <= row.reveal.frame.minX)
        #expect(row.reason.frame.height >= (row.reason.cell?.cellSize(forBounds: NSRect(x: 0, y: 0, width: row.reason.frame.width, height: 1_000)).height ?? 0))
        #expect(rowRect.height >= 24 + row.reason.frame.height)
    }

    @Test func `double-clicking an unreadable row reveals it; selecting it opens nothing`() throws {
        try write(Data("not json".utf8), at: "C/Broken.json")
        var revealed: [String] = []
        let window = makeWindow()
        let sidebar = sidebar(window) { revealed.append($0) }
        let tabsBefore = window.tabs.map(\.tab.id)

        sidebar.outline.selectRowIndexes([1], byExtendingSelection: false)
        #expect(window.tabs.map(\.tab.id) == tabsBefore)
        sidebar.activate(row: 1)
        #expect(revealed == [root.path + "/C/Broken.json"])
    }

    @Test func `with no Collections the sidebar shows the empty text and the Data Folder path`() throws {
        let sidebar = sidebar(makeWindow())
        #expect(sidebar.outline.enclosingScrollView?.isHidden == true)
        #expect(!sidebar.empty.isHidden)
        #expect(sidebar.emptyText.stringValue == "No Collections yet. Create one, or save a Draft into one with ⌘S.")
        #expect(sidebar.emptyPath.stringValue == (root.path as NSString).abbreviatingWithTildeInPath)
        #expect(sidebar.emptyPath.font == .monospacedSystemFont(ofSize: 11, weight: .regular))
    }

    @Test func `a file added on disk shows without losing what was open`() async throws {
        try put("A", at: "C/F/A.json")
        let window = makeWindow()
        let sidebar = sidebar(window)
        try put("B", at: "C/F/B.json")
        watch.emit(["C/F/B.json"])
        for _ in 0..<100 where sidebar.outline.numberOfRows < 4 { await Task.yield() }
        let names = (0..<sidebar.outline.numberOfRows).map { (sidebar.outline.item(atRow: $0) as? SidebarItem)?.name }
        #expect(names == ["C", "F", "A", "B"])
    }

    @Test func `break-ui: 40 Collections of 500 Requests scroll without a stall`() throws {
        var definition = RequestDefinition.empty
        definition.method = "POST"
        for c in 0..<40 {
            for r in 0..<500 {
                try write(RequestFile.encode(Request(id: RequestID(UUID()), name: "Request \(r)", definition: definition)),
                          at: "Collection \(c)/Request \(r).json")
            }
        }
        let sidebar = sidebar(makeWindow())
        #expect(sidebar.outline.numberOfRows == 40 * 501)
        var worst = Duration.zero
        for row in stride(from: 0, to: sidebar.outline.numberOfRows, by: 2_000) {
            let start = ContinuousClock.now
            sidebar.outline.scrollRowToVisible(row)
            sidebar.view.layoutSubtreeIfNeeded()
            sidebar.outline.displayIfNeeded()
            worst = max(worst, ContinuousClock.now - start)
        }
        #expect(worst < .milliseconds(50), "worst scroll step \(worst)")
    }
}

import AppKit
@testable import Raccoon
import RaccoonData
import RaccoonDomain
import RaccoonTesting
import Testing

@MainActor
struct SidebarActionsTests {
    let base = FolderOperationTests()
    let theme = ThemeEnvironment(catalog: ThemeCatalog.load(), isDark: false)

    /// The sidebar over FolderOperationTests' folder, every row expanded:
    /// 0 Orders · 1 Payments API · 2 Refunds · 3 Create charge.
    func sidebar() throws -> (WindowModel, SidebarViewController) {
        let (window, _) = try base.setUp()
        try Data("{".utf8).write(to: base.root.appending(path: "Orders/Broken.json"))
        window.loadDataFolder()
        let sidebar = SidebarViewController(window: window, theme: theme, reveal: { _ in })
        sidebar.view.frame = NSRect(x: 0, y: 0, width: 232, height: 600)
        sidebar.outline.expandItem(nil, expandChildren: true)
        return (window, sidebar)
    }

    func row(_ sidebar: SidebarViewController, _ name: String) throws -> Int {
        try #require((0..<sidebar.outline.numberOfRows).first { (sidebar.outline.item(atRow: $0) as? SidebarItem)?.name == name })
    }

    @Test func `a Request's context menu, with Move To listing the other places`() throws {
        let (_, sidebar) = try sidebar()
        let menu = sidebar.contextMenu(row: try row(sidebar, "Create charge"))
        #expect(menu.items.filter { !$0.isSeparatorItem }.map(\.title) == ["New Folder…", "Rename…", "Move To", "Move to Trash", "Reveal in Finder"])
        #expect(menu.item(withTitle: "Move To")?.submenu?.items.map(\.title) == ["Orders", "Payments API"])
    }

    @Test func `a Collection cannot be moved; an unreadable file cannot be renamed`() throws {
        let (_, sidebar) = try sidebar()
        #expect(sidebar.contextMenu(row: try row(sidebar, "Payments API")).item(withTitle: "Move To") == nil)
        #expect(sidebar.contextMenu(row: try row(sidebar, "Broken.json")).item(withTitle: "Rename…") == nil)
        #expect(sidebar.contextMenu(row: try row(sidebar, "Refunds")).item(withTitle: "Move To")?.submenu?.items.map(\.title) == ["Orders"])
    }

    @Test func `Rename… asks for the name, prefilled, and renames`() throws {
        let (window, sidebar) = try sidebar()
        var asked: [(String, String, String)] = []
        sidebar.askName = { title, initial, button, reply in
            asked.append((title, initial, button))
            reply("Charges")
        }
        let item = try #require(sidebar.contextMenu(row: try row(sidebar, "Refunds")).item(withTitle: "Rename…"))
        _ = (item.target as? NSObject)?.perform(item.action, with: item)

        #expect(asked.map(\.0) == ["Rename"])
        #expect(asked.map(\.1) == ["Refunds"])
        #expect(asked.map(\.2) == ["Rename"])
        #expect(window.index.folders.contains("Payments API/Charges"))
    }

    @Test func `the + menu offers New Collection and New Folder, in the selected row's folder`() throws {
        let (window, sidebar) = try sidebar()
        sidebar.askName = { _, _, _, reply in reply("Webhooks") }
        #expect(sidebar.addMenu.items.map(\.title) == ["New Collection", "New Folder", "", "Import from Postman…"])

        sidebar.outline.selectRowIndexes([try row(sidebar, "Create charge")], byExtendingSelection: false)
        sidebar.addMenu.update()
        #expect(sidebar.addMenu.item(withTitle: "New Folder")?.isEnabled == true)
        sidebar.newFolder(nil)

        #expect(window.index.folders.contains("Payments API/Refunds/Webhooks"))
    }

    @Test func `the + menu's Import from Postman… asks the app to import`() throws {
        let (_, sidebar) = try sidebar()
        var asked = 0
        sidebar.importFromPostman = { asked += 1 }
        let item = try #require(sidebar.addMenu.item(withTitle: "Import from Postman…"))

        _ = (item.target as? NSObject)?.perform(item.action, with: item)

        #expect(asked == 1)
    }

    @Test func `after Postman Import the Collection is selected, past a filter that hid it`() throws {
        let (_, sidebar) = try sidebar()
        sidebar.searchField.stringValue = "Refunds"
        sidebar.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification))

        sidebar.select(path: "Orders")

        #expect(sidebar.searchField.stringValue == "")
        #expect((sidebar.outline.item(atRow: sidebar.outline.selectedRow) as? SidebarItem)?.path == "Orders")
    }

    @Test func `a failed operation says so in an alert`() throws {
        let (_, sidebar) = try sidebar()
        let parent = base.root.appending(path: "Payments API")
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: parent.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: parent.path) }
        var alerts: [String] = []
        sidebar.askName = { _, _, _, reply in reply("Charges") }
        sidebar.showError = { alerts.append($0) }

        let item = try #require(sidebar.contextMenu(row: try row(sidebar, "Refunds")).item(withTitle: "Rename…"))
        _ = (item.target as? NSObject)?.perform(item.action, with: item)

        #expect(alerts == ["Couldn't rename “Refunds”: permission denied."])
    }

    @Test func `the name sheet is disabled while blank`() {
        var reply: String??
        let sheet = NameSheet(title: "New Folder", name: "", button: "Create") { reply = $0 }
        sheet.loadView()
        #expect(sheet.heading.stringValue == "New Folder")
        #expect(sheet.confirmButton.title == "Create")
        #expect(!sheet.confirmButton.isEnabled)
        sheet.nameField.stringValue = "Webhooks"
        sheet.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: sheet.nameField))
        sheet.confirmButton.performClick(nil)
        #expect(reply == "Webhooks")
    }

    @Test func `File ▸ New Collection`() throws {
        let file = try #require(MainMenu.make(theme: ThemeController(defaults: .standard, catalog: ThemeCatalog.load(), appearanceSource: NSView()))
            .item(withTitle: "File")?.submenu)
        #expect(file.item(withTitle: "New Collection")?.action == #selector(AppDelegate.newCollection(_:)))
    }

    @Test func `only a Collection's menu has Export…, after Rename… and before Move to Trash`() throws {
        let (_, sidebar) = try sidebar()
        let titles = { (name: String) in try sidebar.contextMenu(row: row(sidebar, name)).items.filter { !$0.isSeparatorItem }.map(\.title) }

        #expect(try titles("Payments API") == ["New Folder…", "Rename…", "Export…", "Move to Trash", "Reveal in Finder"])
        #expect(try !titles("Refunds").contains("Export…"))
        #expect(try !titles("Create charge").contains("Export…"))
        #expect(try !titles("Broken.json").contains("Export…"))
    }

    @Test func `Export… in a Collection's menu asks the app to export that Collection`() throws {
        let (_, sidebar) = try sidebar()
        var asked: [String] = []
        sidebar.exportCollection = { asked.append($0) }
        let item = try #require(sidebar.contextMenu(row: try row(sidebar, "Orders")).item(withTitle: "Export…"))

        _ = (item.target as? NSObject)?.perform(item.action, with: item)

        #expect(asked == ["Orders"])
    }

    @Test func `the selection is in a Collection when a Collection, a Folder or a Request in it is selected`() throws {
        let (_, sidebar) = try sidebar()
        #expect(sidebar.selectedCollection == nil)
        for (name, collection) in [("Orders", "Orders"), ("Refunds", "Payments API"), ("Create charge", "Payments API"), ("Broken.json", "Orders")] {
            sidebar.outline.selectRowIndexes([try row(sidebar, name)], byExtendingSelection: false)
            #expect(sidebar.selectedCollection == collection, "\(name)")
        }
    }

    @Test func `File ▸ Export Collection… follows Import from Postman…, with no shortcut`() throws {
        let file = try #require(MainMenu.make(theme: ThemeController(defaults: .standard, catalog: ThemeCatalog.load(), appearanceSource: NSView()))
            .item(withTitle: "File")?.submenu)
        let titles = file.items.map(\.title)
        let item = try #require(file.item(withTitle: "Export Collection…"))

        #expect(item.action == #selector(AppDelegate.exportCollection(_:)))
        #expect(item.keyEquivalent == "")
        #expect(titles.firstIndex(of: "Export Collection…") == titles.firstIndex(of: "Import from Postman…")! + 1)
    }

    @Test(arguments: [("Orders", false, true), (nil, false, false), ("Orders", true, false), (nil, true, false)] as [(String?, Bool, Bool)])
    func `Export Collection… is enabled with a Collection selected and no sheet up`(selected: String?, sheetUp: Bool, enabled: Bool) {
        #expect(AppDelegate.canExportCollection(selected: selected, sheetUp: sheetUp) == enabled)
    }

    @Test func `the app's validation disables Export Collection… while a sheet is attached to the window`() throws {
        let (_, sidebar) = try sidebar()
        let controller = MainWindowController(theme: theme, inspector: InspectorMemory(), reduceMotion: { true })
        let delegate = AppDelegate()
        delegate.sidebar = sidebar
        delegate.windowController = controller
        let item = NSMenuItem(title: "Export Collection…", action: #selector(AppDelegate.exportCollection(_:)), keyEquivalent: "")
        let window = try #require(controller.window)

        #expect(!delegate.validateMenuItem(item))
        sidebar.outline.selectRowIndexes([try row(sidebar, "Orders")], byExtendingSelection: false)
        #expect(delegate.validateMenuItem(item))

        let sheet = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 100), styleMask: [.titled], backing: .buffered, defer: false)
        window.beginSheet(sheet, completionHandler: nil)
        #expect(!delegate.validateMenuItem(item))
        window.endSheet(sheet)
    }
}

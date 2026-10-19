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
        #expect(sidebar.addMenu.items.map(\.title) == ["New Collection", "New Folder"])

        sidebar.outline.selectRowIndexes([try row(sidebar, "Create charge")], byExtendingSelection: false)
        sidebar.addMenu.update()
        #expect(sidebar.addMenu.item(withTitle: "New Folder")?.isEnabled == true)
        sidebar.newFolder(nil)

        #expect(window.index.folders.contains("Payments API/Refunds/Webhooks"))
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
}

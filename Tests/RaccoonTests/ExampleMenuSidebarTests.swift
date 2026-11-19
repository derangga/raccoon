import AppKit
@testable import Raccoon
import RaccoonData
import RaccoonDomain
import RaccoonTesting
import Testing

/// The sidebar's New Example, Rename…, Duplicate and Delete… (examples.md, design-system §6 Sidebar rows).
@MainActor
struct ExampleMenuSidebarTests {
    let rows = ExampleRowsTests()
    var requestID: RequestID { rows.requestID }

    func titles(_ menu: NSMenu) -> [String] { menu.items.map { $0.isSeparatorItem ? "-" : $0.title } }

    func choose(_ title: String, in menu: NSMenu) throws {
        let item = try #require(menu.item(withTitle: title))
        _ = (item.target as? NSObject)?.perform(item.action, with: item)
    }

    /// Payments API ▸ Create charge expanded: 0 Payments API · 1 Create charge · 2 Created · 3 Card declined · 4 Ping.
    func expanded() throws -> (WindowModel, SidebarViewController) {
        let (window, sidebar) = try rows.sidebar()
        try rows.expandRequest(sidebar)
        return (window, sidebar)
    }

    func selectedName(_ sidebar: SidebarViewController) -> String? {
        (sidebar.outline.item(atRow: sidebar.outline.selectedRow) as? SidebarItem)?.name
    }

    func key(_ code: UInt16, _ modifiers: NSEvent.ModifierFlags = []) -> NSEvent {
        NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: modifiers, timestamp: 0, windowNumber: 0, context: nil,
                         characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: code)!
    }

    // MARK: Menus

    @Test func `a Request's menu gains New Example beside New Folder…; a Collection's and an Example's do not have it in that place`() throws {
        let (_, sidebar) = try expanded()

        #expect(titles(sidebar.contextMenu(row: 1)) == ["New Folder…", "New Example", "Rename…", "Move To", "-", "Move to Trash", "Reveal in Finder"])
        #expect(sidebar.contextMenu(row: 0).item(withTitle: "New Example") == nil)
        #expect(sidebar.contextMenu(row: 2).item(withTitle: "New Example") == nil)
    }

    @Test func `an Example's menu is Rename…, Duplicate and, apart, Delete…; no Trash, Move or Reveal`() throws {
        let (_, sidebar) = try expanded()

        #expect(titles(sidebar.contextMenu(row: 2)) == ["Rename…", "Duplicate", "-", "Delete…"])
    }

    @Test func `an Example row has a More actions button like a Request's, shown on hover and selection`() throws {
        let (_, sidebar) = try expanded()
        let cell: RequestCell = try rows.base.cell(sidebar, row: 2)
        #expect(cell.more.isHidden)

        cell.hovered = true
        cell.layoutSubtreeIfNeeded()

        #expect(!cell.more.isHidden)
        var opened: [NSMenu] = []
        sidebar.presentMenu = { menu, _ in opened.append(menu) }
        _ = cell.more.target?.perform(cell.more.action, with: cell.more)
        #expect(opened.map(titles) == [["Rename…", "Duplicate", "-", "Delete…"]])
    }

    // MARK: New Example

    @Test func `New Example makes a 200 Example, opens its Tab, expands the Request and selects the new row`() throws {
        let (window, sidebar) = try rows.sidebar()

        try choose("New Example", in: sidebar.contextMenu(row: try rows.row(sidebar, "Create charge")))

        #expect(rows.names(sidebar) == ["Payments API", "Create charge", "Created", "Card declined", "New Example", "Ping"])
        #expect(selectedName(sidebar) == "New Example")
        #expect(sidebar.outline.isItemExpanded(try #require(sidebar.item(path: rows.path))))
        let cell: RequestCell = try rows.base.cell(sidebar, row: 4)
        #expect(cell.badge.stringValue == "200")
        let tab = try #require(window.selectedTab)
        #expect(tab.tab.example?.name == "New Example" && tab.tab.example?.body == .text(""))
    }

    @Test func `a failed New Example is an alert with the reason, and nothing is written or opened`() throws {
        let (window, sidebar) = try rows.sidebar()
        let folder = rows.base.root.appending(path: "Payments API")
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: folder.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: folder.path) }
        var alerts: [String] = []
        sidebar.showError = { alerts.append($0) }
        let tabs = window.tabs.count

        try choose("New Example", in: sidebar.contextMenu(row: try rows.row(sidebar, "Create charge")))

        #expect(alerts.count == 1 && alerts[0].hasPrefix("Couldn't create an Example: "))
        #expect(window.tabs.count == tabs)
        #expect(rows.names(sidebar) == ["Payments API", "Create charge", "Ping"])
    }

    // MARK: Rename…

    @Test func `Rename… on an Example asks with its name, and any non-empty name goes, even a repeated one`() async throws {
        let (window, sidebar) = try expanded()
        window.openExample(requestID, rows.example(1, "Created", status: 201).id)
        var asked: [[String]] = []
        sidebar.askName = { title, name, button, reply in
            asked.append([title, name, button])
            reply("Card declined")
        }

        try choose("Rename…", in: sidebar.contextMenu(row: 2))
        await Task.yield()

        #expect(asked == [["Rename", "Created", "Rename"]])
        #expect(rows.names(sidebar) == ["Payments API", "Create charge", "Card declined", "Card declined", "Ping"])
        #expect(window.selectedTab?.tab.example?.name == "Card declined")
    }

    @Test func `Cancel in the name sheet renames nothing`() throws {
        let (_, sidebar) = try expanded()
        sidebar.askName = { _, _, _, reply in reply(nil) }

        try choose("Rename…", in: sidebar.contextMenu(row: 2))

        #expect(rows.names(sidebar) == ["Payments API", "Create charge", "Created", "Card declined", "Ping"])
    }

    // MARK: Duplicate

    @Test func `Duplicate puts "<name> 2" right after the original and selects it; the original and the Tabs stay`() throws {
        let (window, sidebar) = try expanded()
        let tabs = window.tabs.map(\.tab.id)

        try choose("Duplicate", in: sidebar.contextMenu(row: 2))

        #expect(rows.names(sidebar) == ["Payments API", "Create charge", "Created", "Created 2", "Card declined", "Ping"])
        #expect(selectedName(sidebar) == "Created 2")
        #expect(window.tabs.map(\.tab.id) == tabs)
        let cell: RequestCell = try rows.base.cell(sidebar, row: 3)
        #expect(cell.badge.stringValue == "201")
    }

    // MARK: Delete…

    @Test func `Delete… asks about the Example, Cancel deletes nothing`() throws {
        let (_, sidebar) = try expanded()
        var asked: [String] = []
        sidebar.confirmDeleteExample = { name, reply in asked.append(name); reply(false) }

        try choose("Delete…", in: sidebar.contextMenu(row: 3))

        #expect(asked == ["Card declined"])
        #expect(rows.names(sidebar) == ["Payments API", "Create charge", "Created", "Card declined", "Ping"])
    }

    @Test func `with no sheet wired the answer is no: nothing is deleted`() throws {
        let (_, sidebar) = try expanded()

        try choose("Delete…", in: sidebar.contextMenu(row: 3))

        #expect(rows.names(sidebar) == ["Payments API", "Create charge", "Created", "Card declined", "Ping"])
    }

    @Test func `confirming Delete… removes the Example, and its open Tab stays as Deleted on disk`() async throws {
        let (window, sidebar) = try expanded()
        window.openExample(requestID, rows.example(2, "Card declined", status: 402).id)
        let tab = try #require(window.selectedTab)
        sidebar.confirmDeleteExample = { _, reply in reply(true) }

        try choose("Delete…", in: sidebar.contextMenu(row: 3))
        await Task.yield()

        #expect(rows.names(sidebar) == ["Payments API", "Create charge", "Created", "Ping"])
        #expect(window.tabs.contains { $0 === tab })
        #expect(tab.notice == .exampleDeletedOnDisk && tab.tab.baseline == nil)
    }

    @Test func `a failed delete is an alert with the reason and the Example stays`() throws {
        let (_, sidebar) = try expanded()
        let folder = rows.base.root.appending(path: "Payments API")
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: folder.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: folder.path) }
        var alerts: [String] = []
        sidebar.showError = { alerts.append($0) }
        sidebar.confirmDeleteExample = { _, reply in reply(true) }

        try choose("Delete…", in: sidebar.contextMenu(row: 3))

        #expect(alerts.count == 1 && alerts[0].hasPrefix("Couldn't delete the Example “Card declined”: "))
        #expect(rows.names(sidebar) == ["Payments API", "Create charge", "Created", "Card declined", "Ping"])
    }

    @Test(arguments: [UInt16(51), UInt16(117)])
    func `⌫ and Forward Delete on a selected Example row ask the same question`(code: UInt16) throws {
        let (_, sidebar) = try expanded()
        var asked: [String] = []
        sidebar.confirmDeleteExample = { name, reply in asked.append(name); reply(false) }
        sidebar.outline.selectRowIndexes([2], byExtendingSelection: false)

        sidebar.outline.keyDown(with: key(code))

        #expect(asked == ["Created"])
    }

    @Test(arguments: [NSEvent.ModifierFlags.command, .option, .shift, .control])
    func `⌫ with a modifier on an Example row asks nothing`(modifier: NSEvent.ModifierFlags) throws {
        let (_, sidebar) = try expanded()
        var asked = 0
        sidebar.confirmDeleteExample = { _, _ in asked += 1 }
        sidebar.outline.selectRowIndexes([2], byExtendingSelection: false)

        sidebar.outline.keyDown(with: key(51, modifier))
        sidebar.outline.keyDown(with: key(117, modifier))
        #expect(asked == 0)

        sidebar.outline.keyDown(with: key(51))
        #expect(asked == 1)
    }

    @Test func `⌫ on a Request row, a Collection row or with nothing selected asks nothing and trashes nothing`() throws {
        let (_, sidebar) = try expanded()
        var asked = 0
        sidebar.confirmDeleteExample = { _, _ in asked += 1 }

        for row in [1, 0] {
            sidebar.outline.selectRowIndexes([row], byExtendingSelection: false)
            sidebar.outline.keyDown(with: key(51))
        }
        sidebar.outline.deselectAll(nil)
        sidebar.outline.keyDown(with: key(51))

        #expect(asked == 0)
        #expect(rows.names(sidebar) == ["Payments API", "Create charge", "Created", "Card declined", "Ping"])
    }

    // MARK: The confirmation

    @Test func `the confirmation reads "Delete the Example “<name>”?", with Cancel first (the default and Esc) and Delete second`() {
        let alert = DeleteExampleConfirm.alert(name: "Card declined")
        alert.layout()

        #expect(alert.messageText == "Delete the Example “Card declined”?")
        #expect(alert.informativeText == "It is removed from its Request's file, not moved to the Trash. This can't be undone.")
        // AppKit makes the first button the default; the one titled Cancel also takes Esc.
        #expect(alert.buttons.map(\.title) == ["Cancel", "Delete"])
        #expect(alert.buttons.map(\.keyEquivalent) == ["\u{1B}", ""])
        #expect(alert.buttons[1].hasDestructiveAction)
        #expect(alert.alertStyle == .warning)
    }
}

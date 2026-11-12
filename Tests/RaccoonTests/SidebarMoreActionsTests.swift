import AppKit
@testable import Raccoon
import Testing

/// The ⋯ button on a sidebar row (design-system §6 Sidebar rows, More actions).
@MainActor
struct SidebarMoreActionsTests {
    let base = SidebarActionsTests()

    /// The sidebar over SidebarActionsTests' folder, laid out: Orders · Payments API · Refunds · Create charge · Broken.json.
    func sidebar() throws -> SidebarViewController {
        let sidebar = try base.sidebar().1
        sidebar.view.layoutSubtreeIfNeeded()
        return sidebar
    }

    func cell(_ sidebar: SidebarViewController, _ name: String) throws -> MoreActionsCell {
        let row = try base.row(sidebar, name)
        let cell = try #require(sidebar.outline.view(atColumn: 0, row: row, makeIfNecessary: true) as? MoreActionsCell)
        cell.layoutSubtreeIfNeeded()
        return cell
    }

    /// Collection, Folder, Request, Unreadable.
    nonisolated static let names = ["Payments API", "Refunds", "Create charge", "Broken.json"]

    @Test(arguments: names) func `hover shows the button and leaving hides it`(name: String) throws {
        let cell = try cell(try sidebar(), name)
        #expect(cell.more.isHidden)

        cell.hovered = true
        cell.layoutSubtreeIfNeeded()
        #expect(!cell.more.isHidden)

        cell.hovered = false
        cell.layoutSubtreeIfNeeded()
        #expect(cell.more.isHidden)
    }

    @Test func `the selected row keeps it while the pointer is away, and loses it when the selection moves`() throws {
        let sidebar = try sidebar()
        let (create, refunds) = (try cell(sidebar, "Create charge"), try cell(sidebar, "Refunds"))

        sidebar.outline.selectRowIndexes([try base.row(sidebar, "Create charge")], byExtendingSelection: false)
        create.layoutSubtreeIfNeeded()
        #expect(!create.more.isHidden)
        #expect(refunds.more.isHidden)

        sidebar.outline.selectRowIndexes([try base.row(sidebar, "Refunds")], byExtendingSelection: false)
        create.layoutSubtreeIfNeeded()
        refunds.layoutSubtreeIfNeeded()
        #expect(create.more.isHidden)
        #expect(!refunds.more.isHidden)
    }

    @Test func `the button is 16 pt, 6 pt in from the trailing edge, with the tooltip and label More actions`() throws {
        let cell = try cell(try sidebar(), "Refunds")
        #expect(cell.more.frame.size == NSSize(width: 16, height: 16))
        #expect(cell.bounds.maxX - cell.more.frame.maxX == 6)
        #expect(cell.more.toolTip == "More actions")
        #expect(cell.more.accessibilityLabel() == "More actions")
    }

    @Test(arguments: names) func `names end-truncate against the button only while it shows`(name: String) throws {
        let cell = try cell(try sidebar(), name)
        let field = try #require(Mirror(reflecting: cell).children.first { $0.label == "name" }?.value as? NSTextField)
        let resting = field.frame.maxX

        cell.hovered = true
        cell.layoutSubtreeIfNeeded()
        #expect(field.frame.maxX < cell.more.frame.minX)
        #expect(field.frame.maxX < resting)

        cell.hovered = false
        cell.layoutSubtreeIfNeeded()
        #expect(field.frame.maxX == resting)
    }

    @Test func `on an emphasized selection the glyph takes the selected-text colour`() throws {
        let cell = try cell(try sidebar(), "Create charge")
        #expect(cell.more.contentTintColor == .secondaryLabelColor)

        cell.backgroundStyle = .emphasized
        cell.layoutSubtreeIfNeeded()
        #expect(cell.more.contentTintColor == .alternateSelectedControlTextColor)
    }

    @Test(arguments: names) func `a click opens the same menu as a right-click and the selection does not move`(name: String) throws {
        let sidebar = try sidebar()
        let selected = try base.row(sidebar, "Orders")
        sidebar.outline.selectRowIndexes([selected], byExtendingSelection: false)
        var shown: (menu: NSMenu, anchor: NSView)?
        sidebar.presentMenu = { shown = ($0, $1) }
        let cell = try cell(sidebar, name)

        cell.hovered = true
        cell.layoutSubtreeIfNeeded()
        cell.more.performClick(nil)

        let titles = { (menu: NSMenu) in menu.items.map { $0.isSeparatorItem ? "-" : $0.title } }
        let expected = sidebar.contextMenu(row: try base.row(sidebar, name))
        #expect(titles(try #require(shown).menu) == titles(expected))
        #expect(shown?.anchor === cell.more)
        #expect(sidebar.outline.selectedRow == selected)
    }

    @Test func `with no window there is no pointer, so syncing hover clears it`() throws {
        let cell = try cell(try sidebar(), "Refunds")
        cell.hovered = true
        cell.syncHover()
        #expect(!cell.hovered)
    }

    @Test func `a click re-reads the pointer after the menu closes`() throws {
        let sidebar = try sidebar()
        let cell = try cell(sidebar, "Create charge")
        sidebar.presentMenu = { _, _ in }
        cell.hovered = true
        cell.more.performClick(nil)
        #expect(!cell.hovered)
    }
}

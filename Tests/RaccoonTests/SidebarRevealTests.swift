import AppKit
@testable import Raccoon
import RaccoonDomain
import Testing

@MainActor
struct SidebarRevealTests {
    static let charge = "Payments API/Refunds/Create charge.json"
    let actions = SidebarActionsTests()

    /// The sidebar with every row collapsed, in a window with another field holding focus.
    func collapsed() throws -> (WindowModel, SidebarViewController, NSResponder?) {
        let (window, sidebar) = try actions.sidebar()
        sidebar.outline.collapseItem(nil, collapseChildren: true)
        let host = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 232, height: 640), styleMask: [.titled], backing: .buffered, defer: true)
        let elsewhere = NSTextField(frame: NSRect(x: 0, y: 600, width: 200, height: 24))
        host.contentView?.addSubview(sidebar.view)
        host.contentView?.addSubview(elsewhere)
        host.makeFirstResponder(elsewhere)
        sidebar.view.layoutSubtreeIfNeeded()
        return (window, sidebar, host.firstResponder)
    }

    func selected(_ sidebar: SidebarViewController) -> String? {
        (sidebar.outline.item(atRow: sidebar.outline.selectedRow) as? SidebarItem)?.path
    }

    func isExpanded(_ sidebar: SidebarViewController, _ path: String) -> Bool {
        sidebar.item(path: path).map(sidebar.outline.isItemExpanded) ?? false
    }

    func filter(_ sidebar: SidebarViewController, _ text: String) {
        sidebar.searchField.stringValue = text
        sidebar.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification))
    }

    @Test func `a row two levels down is selected, in view, its ancestors open, focus and Tabs untouched`() throws {
        let (window, sidebar, elsewhere) = try collapsed()
        let tabs = window.tabs.map(\.tab.id)

        #expect(sidebar.reveal(path: Self.charge))

        #expect(selected(sidebar) == Self.charge)
        #expect(["Payments API", "Payments API/Refunds"].allSatisfy { isExpanded(sidebar, $0) })
        #expect(sidebar.outline.visibleRect.contains(sidebar.outline.rect(ofRow: sidebar.outline.selectedRow)))
        #expect(sidebar.view.window?.firstResponder === elsewhere)
        #expect(window.tabs.map(\.tab.id) == tabs)
    }

    @Test func `a Folder's own row is selected and left as it is, collapsed`() throws {
        let (_, sidebar, _) = try collapsed()

        #expect(sidebar.reveal(path: "Payments API/Refunds"))

        #expect(selected(sidebar) == "Payments API/Refunds")
        #expect(isExpanded(sidebar, "Payments API"))
        #expect(!isExpanded(sidebar, "Payments API/Refunds"))
    }

    @Test func `a filter that hides the row is cleared first`() throws {
        let (_, sidebar, _) = try collapsed()
        filter(sidebar, "Orders")

        #expect(sidebar.reveal(path: Self.charge))

        #expect(sidebar.searchField.stringValue == "")
        #expect(selected(sidebar) == Self.charge)
    }

    @Test func `a filter that shows the row is left as it is`() throws {
        let (_, sidebar, _) = try collapsed()
        filter(sidebar, "charge")

        #expect(sidebar.reveal(path: Self.charge))

        #expect(sidebar.searchField.stringValue == "charge")
        #expect(selected(sidebar) == Self.charge)
    }

    @Test func `a path with no row returns false and changes nothing`() throws {
        let (_, sidebar, _) = try collapsed()
        sidebar.outline.selectRowIndexes([0], byExtendingSelection: false)
        filter(sidebar, "Orders")
        let before = selected(sidebar)

        #expect(!sidebar.reveal(path: "Nowhere/Gone.json"))

        #expect(sidebar.searchField.stringValue == "Orders")
        #expect(selected(sidebar) == before)
    }

    @Test func `select(path:) reveals and then focuses the outline`() throws {
        let (_, sidebar, _) = try collapsed()

        #expect(sidebar.select(path: "Orders"))

        #expect(selected(sidebar) == "Orders")
        #expect(sidebar.view.window?.firstResponder === sidebar.outline)
    }

    @Test func `select(path:) with no row focuses nothing`() throws {
        let (_, sidebar, elsewhere) = try collapsed()

        #expect(!sidebar.select(path: "Nowhere"))

        #expect(sidebar.view.window?.firstResponder === elsewhere)
    }
}

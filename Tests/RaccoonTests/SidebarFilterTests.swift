import AppKit
@testable import Raccoon
import RaccoonData
import RaccoonDomain
import RaccoonTesting
import Testing

@MainActor
struct SidebarFilterTests {
    let base = SidebarTests()
    let theme = ThemeEnvironment(catalog: ThemeCatalog.load(), isDark: false)

    /// Board 11's folder: Auth Service, and Payments API with Refund charge and Refunds/{List refunds, Cancel refund}.
    func sidebar() throws -> (WindowModel, SidebarViewController) {
        try base.put("Login", at: "Auth Service/Login.json")
        try base.put("Refund charge", method: "POST", at: "Payments API/Refund charge.json")
        try base.put("List refunds", at: "Payments API/Refunds/List refunds.json")
        try base.put("Cancel refund", method: "DELETE", at: "Payments API/Refunds/Cancel refund.json")
        let window = base.makeWindow()
        let sidebar = base.sidebar(window)
        return (window, sidebar)
    }

    func type(_ query: String, in sidebar: SidebarViewController) {
        sidebar.searchField.stringValue = query
        sidebar.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: sidebar.searchField))
        sidebar.view.layoutSubtreeIfNeeded()
    }

    func names(_ sidebar: SidebarViewController) -> [String] {
        (0..<sidebar.outline.numberOfRows).compactMap { (sidebar.outline.item(atRow: $0) as? SidebarItem)?.name }
    }

    func nameField(_ sidebar: SidebarViewController, row: Int) -> NSTextField? {
        (sidebar.outline.view(atColumn: 0, row: row, makeIfNecessary: true) as? RequestCell)?.name
    }

    @Test func `typing narrows the tree, opens the holders of a match and counts them`() throws {
        let (_, sidebar) = try sidebar()
        #expect(!sidebar.searchField.isHidden)
        #expect(sidebar.searchField.placeholderString == "Filter Collections")

        type("refund", in: sidebar)

        #expect(names(sidebar) == ["Payments API", "Refunds", "Cancel refund", "List refunds", "Refund charge"])
        #expect(sidebar.countLabel.stringValue == "4 matches in 1 Collection")
        #expect(!sidebar.countLabel.isHidden)
        #expect(sidebar.sectionLabel.isHidden)
    }

    @Test func `a match is highlighted with the find colour and set semibold`() throws {
        let (_, sidebar) = try sidebar()
        type("refund", in: sidebar)

        let field = try #require(nameField(sidebar, row: 4))
        let text = field.attributedStringValue
        #expect(text.string == "Refund charge")
        #expect(text.attribute(.font, at: 0, effectiveRange: nil) as? NSFont == .systemFont(ofSize: 13, weight: .semibold))
        #expect(text.attribute(.font, at: 7, effectiveRange: nil) as? NSFont == .systemFont(ofSize: 13))
        #expect(text.attribute(.backgroundColor, at: 0, effectiveRange: nil) as? NSColor == .findHighlightColor)
        #expect(text.attribute(.backgroundColor, at: 7, effectiveRange: nil) == nil)
    }

    @Test func `letters in order with gaps match, each run highlighted apart`() throws {
        let (_, sidebar) = try sidebar()
        type("refnd", in: sidebar)

        #expect(names(sidebar) == ["Payments API", "Refunds", "Cancel refund", "List refunds", "Refund charge"])
        let text = try #require(nameField(sidebar, row: 4)).attributedStringValue
        #expect(text.string == "Refund charge")
        let semibold = NSFont.systemFont(ofSize: 13, weight: .semibold)
        #expect((0..<7).map { text.attribute(.font, at: $0, effectiveRange: nil) as? NSFont == semibold }
            == [true, true, true, false, true, true, false])
    }

    @Test func `no matches says so in place of the tree`() throws {
        let (_, sidebar) = try sidebar()
        type("graphql", in: sidebar)

        #expect(sidebar.outline.enclosingScrollView?.isHidden == true)
        #expect(sidebar.noMatches.stringValue == "No Requests, Folders or Collections match “graphql”.\nEsc clears the filter.")
        #expect(!sidebar.noMatches.isHidden)
    }

    @Test func `Esc clears and brings back the earlier expansion; a second Esc focuses the editor`() throws {
        let (_, sidebar) = try sidebar()
        sidebar.outline.collapseItem(nil, collapseChildren: true)
        let item = try #require(sidebar.outline.item(atRow: 1) as? SidebarItem)  // Payments API
        sidebar.outline.expandItem(item)
        let before = names(sidebar)
        var focused = 0
        sidebar.focusEditor = { focused += 1 }

        type("refund", in: sidebar)
        #expect(sidebar.cancel())
        #expect(sidebar.searchField.stringValue == "")
        #expect(names(sidebar) == before)
        #expect(focused == 0)

        #expect(sidebar.cancel())
        #expect(focused == 1)
    }

    @Test func `Return opens the selected match, or the first, and focuses the editor`() throws {
        let (window, sidebar) = try sidebar()
        var focused = 0
        sidebar.focusEditor = { focused += 1 }
        type("refund", in: sidebar)

        sidebar.returnPressed()

        #expect(window.name(of: try #require(window.selectedTab).tab) == "Cancel refund")
        #expect(focused == 1)
    }

    @Test func `the field is hidden while there are no Collections`() throws {
        let sidebar = base.sidebar(base.makeWindow())
        #expect(sidebar.searchField.isHidden)
    }

    @Test func `a file added while filtering re-runs the filter`() async throws {
        let (_, sidebar) = try sidebar()
        type("refund", in: sidebar)
        try base.put("Refund status", at: "Payments API/Refund status.json")
        base.watch.emit(["Payments API/Refund status.json"])
        for _ in 0..<100 where sidebar.countLabel.stringValue != "5 matches in 1 Collection" { await Task.yield() }

        #expect(sidebar.countLabel.stringValue == "5 matches in 1 Collection")
        #expect(names(sidebar).contains("Refund status"))
    }

    @Test func `break-ui: 2,000 matches scroll and the count says how many`() throws {
        for c in 0..<4 {
            for r in 0..<500 { try base.put("Request \(r)", at: "C\(c)/R\(r).json") }
        }
        let sidebar = base.sidebar(base.makeWindow())
        type("request", in: sidebar)

        #expect(sidebar.countLabel.stringValue == "2,000 matches in 4 Collections")
        #expect(sidebar.outline.numberOfRows == 2_004)
        let start = ContinuousClock.now
        sidebar.outline.scrollRowToVisible(2_003)
        sidebar.view.layoutSubtreeIfNeeded()
        #expect(ContinuousClock.now - start < .milliseconds(100))
    }

    @Test func `a selected row's name turns the selected-text colour and keeps its highlight`() throws {
        let (_, sidebar) = try sidebar()
        type("refund", in: sidebar)
        let cell = try #require(sidebar.outline.view(atColumn: 0, row: 4, makeIfNecessary: true) as? RequestCell)

        cell.backgroundStyle = .emphasized

        let text = cell.name.attributedStringValue
        #expect(text.attribute(.foregroundColor, at: 8, effectiveRange: nil) as? NSColor == .alternateSelectedControlTextColor)
        #expect(text.attribute(.font, at: 0, effectiveRange: nil) as? NSFont == .systemFont(ofSize: 13, weight: .semibold))
    }

    func host(_ sidebar: SidebarViewController) -> NSWindow {
        let window = NSWindow(contentRect: sidebar.view.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = sidebar.view
        return window
    }

    @Test func `⌥⌘F puts the caret in the filter field`() throws {
        let (_, sidebar) = try sidebar()
        let window = host(sidebar)

        sidebar.focusFilter()

        #expect(sidebar.searchField.currentEditor() != nil)
        #expect(window.firstResponder === sidebar.searchField.currentEditor())
    }

    @Test func `with no Collections the hidden field takes no focus`() {
        let sidebar = base.sidebar(base.makeWindow())
        let window = host(sidebar)
        #expect(sidebar.searchField.isHidden)

        sidebar.focusFilter()

        #expect(sidebar.searchField.currentEditor() == nil)
        #expect(window.firstResponder === window)
    }
}

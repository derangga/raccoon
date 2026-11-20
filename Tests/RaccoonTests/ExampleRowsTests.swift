import AppKit
@testable import Raccoon
import RaccoonData
import RaccoonDomain
import RaccoonTesting
import Testing

/// A Request's Examples as child rows in the sidebar (design-system §6 Sidebar rows).
@MainActor
struct ExampleRowsTests {
    let base = SidebarTests()
    let requestID = RequestID(UUID(uuidString: "00000000-0000-4000-8000-0000000000A1")!)
    let path = "Payments API/Create charge.json"

    func example(_ n: Int, _ name: String, status: Int) -> Example {
        Example(id: ExampleID(UUID(uuidString: "00000000-0000-4000-8000-00000000E\(String(format: "%03d", n))")!),
                name: name, status: status, body: .text(""))
    }

    /// Payments API with Create charge (two Examples: "Created" 201, "Card declined" 402) and Ping (none).
    /// Only the Collection is open: Requests stay as the outline leaves them.
    func sidebar() throws -> (WindowModel, SidebarViewController) {
        try base.write(RequestFile.encode(Request(
            id: requestID, name: "Create charge", definition: .empty,
            examples: [example(1, "Created", status: 201), example(2, "Card declined", status: 402)])), at: path)
        try base.put("Ping", at: "Payments API/Ping.json")
        let window = base.makeWindow()
        window.loadDataFolder()
        let sidebar = SidebarViewController(window: window, theme: base.theme, reveal: { _ in })
        sidebar.view.frame = NSRect(x: 0, y: 0, width: 232, height: 700)
        sidebar.outline.expandItem(sidebar.item(path: "Payments API"))
        // The outline autosaves expansion by path in the user defaults: start from the default, not from an earlier test's.
        sidebar.item(path: path).map { sidebar.outline.collapseItem($0) }
        sidebar.view.layoutSubtreeIfNeeded()
        return (window, sidebar)
    }

    func names(_ sidebar: SidebarViewController) -> [String] {
        (0..<sidebar.outline.numberOfRows).compactMap { (sidebar.outline.item(atRow: $0) as? SidebarItem)?.name }
    }

    func row(_ sidebar: SidebarViewController, _ name: String) throws -> Int {
        try #require((0..<sidebar.outline.numberOfRows).first { (sidebar.outline.item(atRow: $0) as? SidebarItem)?.name == name })
    }

    func expandRequest(_ sidebar: SidebarViewController) throws {
        sidebar.outline.expandItem(try #require(sidebar.item(path: path)))
        sidebar.view.layoutSubtreeIfNeeded()
    }

    @Test func `a Request with Examples starts collapsed and has a disclosure triangle; one without has none`() throws {
        let (_, sidebar) = try sidebar()
        let outline = sidebar.outline

        #expect(names(sidebar) == ["Payments API", "Create charge", "Ping"])
        #expect(outline.isExpandable(try #require(sidebar.item(path: path))))
        #expect(!outline.isExpandable(try #require(sidebar.item(path: "Payments API/Ping.json"))))
    }

    @Test func `expanded, the Examples follow in file order one level deeper, 24 pt high`() throws {
        let (_, sidebar) = try sidebar()
        try expandRequest(sidebar)
        let outline = sidebar.outline

        #expect(names(sidebar) == ["Payments API", "Create charge", "Created", "Card declined", "Ping"])
        #expect((0..<5).map(outline.level(forRow:)) == [0, 1, 2, 2, 1])
        #expect(outline.rect(ofRow: 2).height == 24)
    }

    @Test(arguments: [(2, 201, ColorToken.status2xx), (3, 402, .status4xx)])
    func `an Example row shows its status in SF Mono bold 9.5 pt, coloured by class, then its name`(row: Int, status: Int, token: ColorToken) throws {
        let (_, sidebar) = try sidebar()
        try expandRequest(sidebar)

        let cell: RequestCell = try base.cell(sidebar, row: row)

        #expect(cell.badge.stringValue == "\(status)")
        #expect(cell.badge.textColor == base.theme.color(token))
        #expect(cell.badge.font == .monospacedSystemFont(ofSize: 9.5, weight: .bold))
        #expect(cell.name.stringValue == (row == 2 ? "Created" : "Card declined"))
        #expect(cell.more.isHidden)
    }

    @Test func `an Example row opens its Tab on a click and on Return`() throws {
        let (window, sidebar) = try sidebar()
        try expandRequest(sidebar)

        sidebar.open(row: 2)
        sidebar.activate(row: 2)

        guard case .example = window.selectedTab?.tab.source else { Issue.record("no Example Tab"); return }
        #expect(window.tabs.filter { $0.tab.example != nil }.count == 1)
    }

    @Test func `a filter on an Example's name shows its Request open with only that Example, highlighted`() throws {
        let (_, sidebar) = try sidebar()
        sidebar.searchField.stringValue = "declined"
        sidebar.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: sidebar.searchField))
        sidebar.view.layoutSubtreeIfNeeded()

        #expect(names(sidebar) == ["Payments API", "Create charge", "Card declined"])
        #expect(sidebar.countLabel.stringValue == "1 match in 1 Collection")
        let cell: RequestCell = try base.cell(sidebar, row: 2)
        #expect(cell.name.attributedStringValue.attribute(.backgroundColor, at: 5, effectiveRange: nil) as? NSColor == .findHighlightColor)

        sidebar.searchField.stringValue = ""
        sidebar.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: sidebar.searchField))
        #expect(names(sidebar) == ["Payments API", "Create charge", "Ping"])
    }

    @Test func `an open Request stays open when its Examples change, and the sidebar follows with no disk scan`() async throws {
        let (window, sidebar) = try sidebar()
        try expandRequest(sidebar)

        try window.addExample(example(3, "Server error", status: 500), to: requestID)
        await Task.yield()
        sidebar.view.layoutSubtreeIfNeeded()
        #expect(names(sidebar) == ["Payments API", "Create charge", "Created", "Card declined", "Server error", "Ping"])

        try window.removeExample(requestID, example(1, "", status: 0).id)
        await Task.yield()
        #expect(names(sidebar) == ["Payments API", "Create charge", "Card declined", "Server error", "Ping"])
    }

    @Test func `a collapsed Request stays collapsed when an Example is added`() async throws {
        let (window, sidebar) = try sidebar()

        try window.addExample(example(3, "Server error", status: 500), to: requestID)
        await Task.yield()

        #expect(names(sidebar) == ["Payments API", "Create charge", "Ping"])
    }

    @Test func `a Request matched by its own name opens when an Example's name matches too, so the count is all visible`() throws {
        let (_, sidebar) = try sidebar()
        sidebar.searchField.stringValue = "cre"
        sidebar.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: sidebar.searchField))
        sidebar.view.layoutSubtreeIfNeeded()

        #expect(names(sidebar) == ["Payments API", "Create charge", "Created", "Card declined"])
        #expect(sidebar.countLabel.stringValue == "3 matches in 1 Collection")
    }

    @Test func `removing the last Example takes the triangle away; adding one back shows it collapsed`() async throws {
        let (window, sidebar) = try sidebar()
        try window.removeExample(requestID, example(1, "", status: 0).id)
        try window.removeExample(requestID, example(2, "", status: 0).id)
        await Task.yield()
        #expect(!sidebar.outline.isExpandable(try #require(sidebar.item(path: path))))

        try window.addExample(example(3, "Server error", status: 500), to: requestID)
        await Task.yield()

        #expect(sidebar.outline.isExpandable(try #require(sidebar.item(path: path))))
        #expect(names(sidebar) == ["Payments API", "Create charge", "Ping"])
    }

    @Test func `revealing an Example just added opens its Request and selects its row, leaving the Tabs and the other rows alone`() throws {
        let (window, sidebar) = try sidebar()
        let tabs = window.tabs.map(\.tab.id)
        let new = example(3, "200 OK", status: 200)
        try window.addExample(new, to: requestID)

        #expect(sidebar.reveal(path: new.path))

        #expect(names(sidebar) == ["Payments API", "Create charge", "Created", "Card declined", "200 OK", "Ping"])
        #expect(sidebar.outline.isItemExpanded(try #require(sidebar.item(path: path))))
        #expect((sidebar.outline.item(atRow: sidebar.outline.selectedRow) as? SidebarItem)?.path == new.path)
        #expect(window.tabs.map(\.tab.id) == tabs)
    }

    @Test func `revealing an Example under a collapsed Collection opens the Collection too`() throws {
        let (_, sidebar) = try sidebar()
        sidebar.outline.collapseItem(nil, collapseChildren: true)
        let first = example(1, "", status: 0)

        #expect(sidebar.reveal(path: first.path))

        #expect(["Payments API", path].allSatisfy { sidebar.item(path: $0).map(sidebar.outline.isItemExpanded) == true })
        #expect((sidebar.outline.item(atRow: sidebar.outline.selectedRow) as? SidebarItem)?.name == "Created")
    }
}

private extension Example {
    /// Its sidebar row, under the Request that `ExampleRowsTests` writes.
    var path: String { ExampleSummary(self).path(in: "Payments API/Create charge.json") }
}

/// A name the trailing ⋯ or the edge cuts short shows in full as a tooltip.
@MainActor
struct CutNameTooltipTests {
    @Test func `a name that fits has no tooltip, one cut short shows in full, and a hovered row cuts earlier`() throws {
        let cell = NodeCell(target: NSObject(), action: #selector(NSObject.description))
        cell.name.stringValue = "Payments API with a long name"
        cell.frame = NSRect(x: 0, y: 0, width: 400, height: 24)
        cell.layout()
        #expect(cell.name.toolTip == nil)

        cell.frame = NSRect(x: 0, y: 0, width: 100, height: 24)
        cell.layout()
        #expect(cell.name.toolTip == "Payments API with a long name")

        cell.name.stringValue = "API"
        cell.frame = NSRect(x: 0, y: 0, width: 60, height: 24)
        cell.layout()
        #expect(cell.name.toolTip == nil)
        cell.hovered = true
        cell.layout()
        #expect(cell.name.toolTip == "API")
    }

    @Test func `a name the button leaves no room for ends in an ellipsis on one line, it does not wrap`() throws {
        let cell = NodeCell(target: NSObject(), action: #selector(NSObject.description))
        cell.name.attributedStringValue = NSAttributedString(string: "Get Product Detail")
        cell.name.stringValue = "Get Product Detail"
        let item = SidebarItem(kind: .folder, name: "Get Product Detail", path: "Get Product Detail")
        cell.show(item, match: [])
        cell.frame = NSRect(x: 0, y: 0, width: 100, height: 24)
        cell.layout()

        let style = try #require(cell.name.attributedStringValue.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle)
        #expect(style.lineBreakMode == .byTruncatingTail)
        let font = try #require(cell.name.attributedStringValue.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)
        // Drawn as one line: truncation keeps the height of one line, wrapping would ask for two.
        #expect(cell.name.cell?.cellSize(forBounds: cell.name.bounds).height ?? 0 <= font.boundingRectForFont.height + 1)
    }
}


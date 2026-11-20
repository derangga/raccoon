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
        // What a draw pass does first; these views are not in a window, so nothing else would.
        cell.viewWillDraw()
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

    @Test func `the button is 18 pt, 14 pt in from the outline's edge (4 pt inside the selection), with the tooltip and label More actions`() throws {
        let cell = try cell(try sidebar(), "Refunds")
        #expect(cell.more.frame.size == NSSize(width: 18, height: 18))
        // It reaches into the inset the source-list style leaves right of the cell, so it is 14 pt from the outline, not the cell.
        #expect(cell.trailingInset > 0)
        #expect(try gapToOutlineEdge(of: cell) == 14)
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

    @Test func `the name still stops 4 pt short of the button while it shows, and takes the freed inset back`() throws {
        let cell = try cell(try sidebar(), "Refunds")
        let field = try #require(Mirror(reflecting: cell).children.first { $0.label == "name" }?.value as? NSTextField)
        cell.hovered = true
        cell.layoutSubtreeIfNeeded()
        #expect(cell.more.frame.minX - field.frame.maxX == 4)
        // The reserve is what the inset does not hold: 36 less the inset.
        #expect(cell.moreReserve == 36 - cell.trailingInset)
    }

    @Test func `a click on the part of the button that is past the cell reaches the button, and hover covers it`() throws {
        let sidebar = try sidebar()
        let cell = try cell(sidebar, "Refunds")
        cell.hovered = true
        cell.layoutSubtreeIfNeeded()
        let outline = sidebar.outline
        let inCell = outline.convert(NSPoint(x: cell.more.bounds.midX, y: cell.more.bounds.midY), from: cell.more)
        let past = outline.convert(NSPoint(x: cell.more.bounds.maxX - 1, y: cell.more.bounds.midY), from: cell.more)

        #expect(outline.hitTest(outline.convert(inCell, to: outline.superview)) === cell.more)
        #expect(past.x > outline.convert(NSPoint(x: cell.bounds.maxX, y: 0), from: cell).x)
        #expect(outline.hitTest(outline.convert(past, to: outline.superview)) === cell.more)
        // Hidden, it is not there to hit.
        cell.hovered = false
        cell.layoutSubtreeIfNeeded()
        #expect(outline.hitTest(outline.convert(past, to: outline.superview)) !== cell.more)
    }

    @Test func `hovering and leaving a row does not replace its tracking area, so no exit event is lost`() throws {
        let cell = try cell(try sidebar(), "Refunds")
        cell.updateTrackingAreas()  // what AppKit does when the cell is placed
        let before = cell.trackingAreas
        #expect(before.count == 1)

        cell.hovered = true
        cell.layoutSubtreeIfNeeded()
        cell.hovered = false
        cell.layoutSubtreeIfNeeded()

        #expect(cell.trackingAreas.count == 1)
        #expect(cell.trackingAreas.first === before.first)
    }

    @Test func `the button lies inside the blue selection with 4 pt to spare on the right and 3 pt above and below`() throws {
        let sidebar = try sidebar()
        let cell = try cell(sidebar, "Create charge")
        let row = try base.row(sidebar, "Create charge")
        sidebar.outline.selectRowIndexes([row], byExtendingSelection: false)
        cell.layoutSubtreeIfNeeded()
        let rowView = try #require(sidebar.outline.rowView(atRow: row, makeIfNecessary: true))
        rowView.isEmphasized = true

        // The highlight is what the row view draws: find its right edge in a bitmap, not by assuming an inset.
        let rep = try #require(rowView.bitmapImageRepForCachingDisplay(in: rowView.bounds))
        rowView.cacheDisplay(in: rowView.bounds, to: rep)
        let scale = CGFloat(rep.pixelsWide) / rowView.bounds.width
        let blue = (0..<rep.pixelsWide).filter { x in
            (0..<rep.pixelsHigh).contains { y in
                guard let c = rep.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { return false }
                return c.alphaComponent > 0.5 && c.blueComponent > c.redComponent + 0.2
            }
        }
        let highlightRight = CGFloat(try #require(blue.max()) + 1) / scale

        let button = rowView.convert(cell.more.bounds, from: cell.more)
        #expect(highlightRight - button.maxX == 4)
        #expect(button.minY - rowView.bounds.minY == 3 || rowView.bounds.maxY - button.maxY == 3)
    }

    /// How far the button's trailing edge is from the outline's, whatever views sit between them.
    func gapToOutlineEdge(of cell: MoreActionsCell) throws -> CGFloat {
        var view = cell.superview
        while let current = view, !(current is NSTableView) { view = current.superview }
        let table = try #require(view)
        return table.bounds.width - cell.convert(NSPoint(x: cell.more.frame.maxX, y: 0), to: table).x
    }

    @Test func `a selected row's button lines up with a hovered row's, even when its cell sits in a narrower view`() throws {
        let sidebar = try sidebar()
        let selected = try cell(sidebar, "Create charge")
        let hovered = try cell(sidebar, "Refunds")
        sidebar.outline.selectRowIndexes([try base.row(sidebar, "Create charge")], byExtendingSelection: false)
        hovered.hovered = true
        selected.layoutSubtreeIfNeeded()
        hovered.layoutSubtreeIfNeeded()
        #expect(try gapToOutlineEdge(of: selected) == 14)
        #expect(try gapToOutlineEdge(of: hovered) == 14)

        // A wrapper narrower than the row, as a selected row may have: the cell's own parent no longer says where the edge is.
        let row = try #require(selected.superview)
        let wrapper = NSView(frame: NSRect(x: 0, y: 0, width: row.bounds.width - 5, height: row.bounds.height))
        row.addSubview(wrapper)
        wrapper.addSubview(selected)
        selected.viewWillDraw()
        selected.layoutSubtreeIfNeeded()
        #expect(try gapToOutlineEdge(of: selected) == 14)
    }
}

/// The button's own hover: the ellipsis alone at rest, a rounded pill under the pointer or a press.
@MainActor
struct MoreButtonPillTests {
    func fill(_ button: MoreButton) -> CGFloat {
        var alpha: CGFloat = 0
        button.effectiveAppearance.performAsCurrentDrawingAppearance {
            alpha = button.layer?.backgroundColor.flatMap(NSColor.init(cgColor:))?.alphaComponent ?? 0
        }
        return alpha
    }

    @Test func `no pill at rest, 18% under the pointer, 28% pressed, and none again when it leaves`() {
        let button = MoreButton(frame: NSRect(x: 0, y: 0, width: 20, height: 20))
        button.refresh()
        #expect(fill(button) == 0)
        #expect(button.layer?.cornerRadius == 5)

        button.mouseEntered(with: NSEvent())
        #expect(abs(fill(button) - 0.18) < 0.01)
        button.isHighlighted = true
        #expect(abs(fill(button) - 0.28) < 0.01)
        button.isHighlighted = false
        button.mouseExited(with: NSEvent())
        #expect(fill(button) == 0)
    }
}

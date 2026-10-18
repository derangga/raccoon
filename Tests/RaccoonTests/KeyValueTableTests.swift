import AppKit
@testable import Raccoon
import RaccoonDomain
import Testing

@MainActor
struct KeyValueTableTests {
    let theme = ThemeEnvironment(catalog: ThemeCatalog.load(), isDark: false)
    let rows = [Row(name: "limit", value: "20"), Row(name: "since", value: "{{since}}", isEnabled: false)]
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 300), styleMask: [], backing: .buffered, defer: false)

    func table(_ rows: [Row]) -> KeyValueTable {
        let table = KeyValueTable(theme: theme)
        table.frame = window.contentView!.bounds
        window.contentView!.addSubview(table)
        table.setRows(rows)
        table.layoutSubtreeIfNeeded()
        return table
    }

    @Test func `the table is as tall as its header and rows, so the last grid line is its border`() {
        let table = table(rows)
        let height: CGFloat = table.intrinsicContentSize.height
        #expect(height == 108)
    }

    @Test func `the placeholder is fainter than a value, and the field fills the row less 2 pt`() throws {
        let table = table(rows)
        let empty = try field(table, column: 1, row: 2)
        let ink = try #require(empty.placeholderAttributedString?.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor)
        #expect(ink.alphaComponent < 1 && ink.alphaComponent > 0)
        #expect(try field(table, column: 1, row: 0).textColor == theme.color(.text))
        table.layoutSubtreeIfNeeded()
        #expect(empty.frame.height == 24)
        // One line tall, in the middle of the 24 pt box.
        let drawn = try #require(empty.cell?.drawingRect(forBounds: empty.bounds))
        #expect(drawn.height < 24 && abs(drawn.midY - empty.bounds.midY) <= 1)
    }

    @Test func `every row draws the one vertical rule at the start of the Value column`() throws {
        let table = table(rows)
        table.setAutomaticRows([AutomaticHeader(name: "Host", value: "example.com")])
        table.layoutSubtreeIfNeeded()
        let rule = theme.color(.border).usingColorSpace(.sRGB)!
        let valueX = Int(table.table.rect(ofColumn: 2).minX)
        for row in 0..<table.table.numberOfRows {
            let view = try #require(table.table.rowView(atRow: row, makeIfNecessary: true))
            let image = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
            view.cacheDisplay(in: view.bounds, to: image)
            let scale = CGFloat(image.pixelsWide) / view.bounds.width
            let middle = Int(view.bounds.height / 2 * scale)
            func color(_ x: Int) -> NSColor { image.colorAt(x: Int(CGFloat(x) * scale), y: middle)!.usingColorSpace(.sRGB)! }
            #expect(abs(color(valueX).redComponent - rule.redComponent) < 0.08, "row \(row)")
            #expect(abs(color(valueX + 10).redComponent - rule.redComponent) > 0.12, "row \(row)")
            #expect(abs(color(valueX - 10).redComponent - rule.redComponent) > 0.12, "row \(row)")
        }
    }

    func field(_ table: KeyValueTable, column: Int, row: Int) throws -> NSTextField {
        try #require((table.table.view(atColumn: column, row: row, makeIfNecessary: true) as? NSTableCellView)?.textField)
    }

    func checkbox(_ table: KeyValueTable, row: Int) throws -> NSButton {
        try #require(table.table.view(atColumn: 0, row: row, makeIfNecessary: true)?.subviews.first as? NSButton)
    }

    func key(_ code: UInt16, _ characters: String) -> NSEvent {
        NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil,
                         characters: characters, charactersIgnoringModifiers: characters, isARepeat: false, keyCode: code)!
    }

    @Test func `the rows are followed by one trailing empty row with Name and Value placeholders`() throws {
        let table = table(rows)
        #expect(table.table.numberOfRows == 3)
        let (name, value) = (try field(table, column: 1, row: 2), try field(table, column: 2, row: 2))
        #expect((name.stringValue, value.stringValue) == ("", ""))
        #expect((name.placeholderAttributedString?.string, value.placeholderAttributedString?.string) == ("Name", "Value"))
        #expect(!(try checkbox(table, row: 2)).isEnabled)
    }

    @Test func `a Disabled Row is unchecked and drawn in textDisabled`() throws {
        let table = table(rows)
        #expect(try checkbox(table, row: 0).state == .on)
        #expect(try field(table, column: 1, row: 0).textColor == theme.color(.text))
        #expect(try checkbox(table, row: 1).state == .off)
        #expect(try field(table, column: 1, row: 1).textColor == theme.color(.textDisabled))
        #expect(try field(table, column: 2, row: 1).textColor == theme.color(.textDisabled))
    }

    @Test func `typing in the trailing row creates a row and a new trailing row`() throws {
        let table = table(rows)
        var sent: [Row] = []
        table.onChange = { sent = $0 }
        let name = try field(table, column: 1, row: 2)
        name.stringValue = "status"
        table.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: name))

        #expect(sent == rows + [Row(name: "status", value: "")])
        #expect(table.table.numberOfRows == 4)
        #expect(try checkbox(table, row: 2).state == .on)
    }

    @Test func `the checkbox flips isEnabled only`() throws {
        let table = table(rows)
        var sent: [Row] = []
        table.onChange = { sent = $0 }
        try checkbox(table, row: 0).performClick(nil)
        #expect(sent == [Row(name: "limit", value: "20", isEnabled: false), rows[1]])
        #expect(try field(table, column: 1, row: 0).textColor == theme.color(.textDisabled))
    }

    @Test func `Space toggles the selected row and Delete removes it`() {
        let table = table(rows)
        var sent: [Row] = []
        table.onChange = { sent = $0 }
        table.table.selectRowIndexes([1], byExtendingSelection: false)
        table.table.keyDown(with: key(49, " "))
        #expect(sent == [rows[0], Row(name: "since", value: "{{since}}")])

        table.table.keyDown(with: key(51, "\u{7F}"))
        #expect(sent == [rows[0]])
        #expect(table.table.numberOfRows == 2)
    }

    @Test func `the trailing row cannot be toggled or deleted from the keyboard`() {
        let table = table(rows)
        var changed = false
        table.onChange = { _ in changed = true }
        table.table.selectRowIndexes([2], byExtendingSelection: false)
        table.table.keyDown(with: key(49, " "))
        table.table.keyDown(with: key(51, "\u{7F}"))
        #expect(!changed)
        #expect(table.table.numberOfRows == 3)
    }

    @Test func `a long value end-truncates with the full value in its tooltip`() throws {
        let jwt = String(repeating: "eyJhbGciOiJIUzI1NiJ9.", count: 60)
        let table = table([Row(name: "Authorization", value: jwt)])
        let value = try field(table, column: 2, row: 0)
        #expect(value.lineBreakMode == .byTruncatingTail)
        #expect(value.stringValue == jwt)
        #expect(value.toolTip == jwt)
    }

    @Test func `sixty rows scroll inside the table under a header that stays put`() throws {
        let table = table((1...60).map { Row(name: "X-Header-\($0)", value: "\($0)") })
        let scroll = try #require(table.table.enclosingScrollView)
        let header = try #require(table.table.headerView)
        #expect(header.isDescendant(of: scroll))
        #expect(!header.isDescendant(of: scroll.contentView))
        #expect(table.table.frame.height > scroll.contentView.bounds.height)
    }

    @Test func `setting the rows it just sent does not reload, so the field editor survives`() throws {
        let table = table(rows)
        let before = try field(table, column: 1, row: 0)
        table.setRows(rows)
        #expect(try field(table, column: 1, row: 0) === before)
    }

    @Test func `automatic rows come first, read-only, with a locked checked box and no delete`() throws {
        let table = table(rows)
        table.setAutomaticRows([AutomaticHeader(name: "Host", value: "example.com"), AutomaticHeader(name: "Content-Length", value: nil)])
        #expect(table.table.numberOfRows == 5)
        let (name, value) = (try field(table, column: 1, row: 0), try field(table, column: 2, row: 0))
        #expect((name.stringValue, value.stringValue) == ("Host", "example.com"))
        #expect(!name.isEditable && !value.isEditable)
        #expect(name.textColor == theme.color(.textTertiary))
        #expect(try field(table, column: 2, row: 1).stringValue == "calculated when sent")
        let box = try #require(table.table.view(atColumn: 0, row: 0, makeIfNecessary: true)?.subviews.first as? NSButton)
        #expect(box.state == .on && !box.isEnabled)
        #expect(table.table.view(atColumn: 3, row: 0, makeIfNecessary: true)?.subviews.isEmpty == true)
        // The user's rows follow, then the empty row last.
        #expect(try field(table, column: 1, row: 2).stringValue == "limit")
        #expect(try field(table, column: 1, row: 4).stringValue == "")
    }

    @Test func `changing the automatic rows keeps the rows below them, so the field editor survives`() throws {
        let table = table(rows)
        table.setAutomaticRows([AutomaticHeader(name: "Host", value: "example.com")])
        let before = try field(table, column: 1, row: 1)
        table.setAutomaticRows([])
        #expect(table.table.numberOfRows == 3)
        #expect(try field(table, column: 1, row: 0) === before)
    }

    @Test func `the keyboard acts on the user's rows below the automatic ones, never on an automatic row`() {
        let table = table(rows)
        table.setAutomaticRows([AutomaticHeader(name: "Host", value: "example.com")])
        #expect(!table.tableView(table.table, shouldSelectRow: 0))
        table.table.selectRowIndexes([1], byExtendingSelection: false)
        table.table.keyDown(with: key(49, " "))
        #expect(table.rows.map(\.isEnabled) == [false, false])
        table.table.keyDown(with: key(51, "\u{7F}"))
        #expect(table.rows.map(\.name) == ["since"])
        #expect(table.table.numberOfRows == 3)
    }
}

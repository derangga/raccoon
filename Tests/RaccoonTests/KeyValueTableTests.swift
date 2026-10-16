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
}

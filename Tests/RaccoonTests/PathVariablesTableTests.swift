import AppKit
@testable import Raccoon
import RaccoonDomain
import RaccoonTesting
import Testing

/// The Params pane's Path Variables table (design-system §6).
@MainActor
struct PathVariablesTableTests {
    let theme = ThemeEnvironment(catalog: ThemeCatalog.load(), isDark: false)
    let model = TabModel(transport: ScriptedTransport(.failure(.timedOut)), secrets: InMemorySecretStore(), files: DictionaryFileReading([:]), instants: FixedInstantSource(.now), clipboard: RecordingClipboardWriter())
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 700, height: 400), styleMask: [.titled], backing: .buffered, defer: false)

    func editor(url: String = "") -> RequestEditor {
        model.typeInURLBar(url)
        let editor = RequestEditor(model: model, theme: theme)
        editor.frame = window.contentView!.bounds
        window.contentView!.addSubview(editor)
        editor.layoutSubtreeIfNeeded()
        return editor
    }

    func valueField(_ editor: RequestEditor, row: Int) throws -> KeyField {
        let table = editor.paramsPane.pathTable.table
        let cell = try #require(table.view(atColumn: 1, row: row, makeIfNecessary: true) as? NSTableCellView)
        return try #require(cell.textField as? KeyField)
    }

    @Test func `with no :name in the URL there is no Path Variables label or table, and Query Params is always there`() {
        let editor = editor(url: "http://localhost:3061/posts")
        #expect(editor.paramsPane.queryLabel.stringValue == "Query Params" && !editor.paramsPane.queryLabel.isHidden)
        #expect(editor.paramsPane.pathLabel.isHidden && editor.paramsPane.pathTable.isHidden)
        #expect(editor.paramsPane.pathLabel.stringValue == "Path Variables")
    }

    @Test func `a :name shows the label and one row per name, Name read-only, Value empty with its placeholder`() throws {
        let editor = editor(url: "http://localhost:3061/posts/:id/retry/:other")
        let pane = editor.paramsPane
        #expect(!pane.pathLabel.isHidden && !pane.pathTable.isHidden)
        #expect(pane.pathTable.table.numberOfRows == 2 && pane.pathTable.table.tableColumns.count == 2)
        #expect(pane.pathTable.table.tableColumns.map(\.title) == ["Name", "Value"])

        let name = try #require((pane.pathTable.table.view(atColumn: 0, row: 0, makeIfNecessary: true) as? NSTableCellView)?.textField)
        #expect(name.stringValue == "id" && !name.isEditable && !name.isSelectable)
        #expect(name.textColor == theme.color(.textSecondary))
        let value = try valueField(editor, row: 1)
        #expect(value.stringValue == "" && value.placeholderAttributedString?.string == "Value" && value.isEditable)
        #expect(pane.pathTable.table.numberOfRows == 2, "no trailing empty row")
        #expect(!pane.pathTable.table.selectedRowIndexes.contains(0))
    }

    @Test func `typing in a Value cell sets that name's value, and clearing it removes it`() throws {
        let editor = editor(url: "http://h/:id")
        let field = try valueField(editor, row: 0)
        field.stringValue = "689eba19be47b88f9d590367"
        editor.paramsPane.pathTable.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: field))
        #expect(model.tab.definition.pathVariables == ["id": "689eba19be47b88f9d590367"])
        field.stringValue = ""
        editor.paramsPane.pathTable.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: field))
        #expect(model.tab.definition.pathVariables == [:])
    }

    @Test func `the value follows the model and a row for a name that leaves the URL goes`() throws {
        let editor = editor(url: "http://h/:a/:b")
        model.setPathVariable("b", to: "2")
        editor.render()
        #expect(try valueField(editor, row: 1).stringValue == "2")
        model.typeInURLBar("http://h/:b")
        editor.render()
        #expect(editor.paramsPane.pathTable.names == ["b"])
        #expect(try valueField(editor, row: 0).stringValue == "2")
        model.typeInURLBar("http://h/x")
        editor.render()
        #expect(editor.paramsPane.pathLabel.isHidden && editor.paramsPane.pathTable.table.numberOfRows == 0)
    }

    @Test func `editing the host, or a row coming and going above, keeps the cell's field editor and caret`() throws {
        let editor = editor(url: "http://h/:id")
        window.makeKeyAndOrderFront(nil)
        defer { window.orderOut(nil) }
        let field = try valueField(editor, row: 0)
        #expect(window.makeFirstResponder(field))
        let fieldEditor = try #require(field.currentEditor() as? NSTextView)
        fieldEditor.insertText("abcdef", replacementRange: fieldEditor.selectedRange())
        fieldEditor.setSelectedRange(NSRange(location: 3, length: 0))
        #expect(model.tab.definition.pathVariables == ["id": "abcdef"])

        model.typeInURLBar("http://other-host/:id")
        editor.render()
        #expect(field.currentEditor() === fieldEditor && fieldEditor.selectedRange() == NSRange(location: 3, length: 0))

        model.typeInURLBar("http://other-host/:a/:id")
        editor.render()
        #expect(editor.paramsPane.pathTable.names == ["a", "id"])
        #expect(field.currentEditor() === fieldEditor && fieldEditor.selectedRange() == NSRange(location: 3, length: 0))
        #expect(window.firstResponder === fieldEditor)
        #expect(fieldEditor.string == "abcdef")

        model.typeInURLBar("http://other-host/:id/:z")
        editor.render()
        #expect(editor.paramsPane.pathTable.names == ["id", "z"])
        #expect(field.currentEditor() === fieldEditor && window.firstResponder === fieldEditor)
    }

    @Test func `30 names scroll the pane as one with no header pinned, and a 2,000-character value is end-truncated`() throws {
        let names = (1...30).map { "n\($0)" }
        let editor = editor(url: "http://h/" + names.map { ":" + $0 }.joined(separator: "/"))
        model.setPathVariable("n1", to: String(repeating: "x", count: 2000))
        editor.render()
        let pane = editor.paramsPane
        #expect(pane.pathTable.table.numberOfRows == 30)
        // One scroll view holds both tables; neither scrolls on its own.
        #expect(pane.pathTable.table.enclosingScrollView?.hasVerticalScroller == false)
        #expect(pane.queryTable.table.enclosingScrollView?.verticalScrollElasticity != nil)
        let document = try #require(pane.scroll.documentView)
        pane.layoutSubtreeIfNeeded()
        #expect(document.frame.height > pane.scroll.contentView.bounds.height)
        #expect(pane.pathTable.intrinsicContentSize.height == CGFloat(24 + 30 * 28))
        #expect(abs(pane.pathTable.frame.height - CGFloat(24 + 30 * 28)) < 0.5)
        #expect(pane.pathTable.isDescendant(of: document) && pane.queryTable.isDescendant(of: document))
        let long = try valueField(editor, row: 0)
        #expect(long.lineBreakMode == .byTruncatingTail && long.stringValue.count == 2000)
    }

    @Test func `a Value cell takes {{ with highlighting and suggestions`() throws {
        model.variables = { (nil, Globals(entries: [VariableEntry(name: VariableName("tenant")!, value: .plain("t"))])) }
        let editor = editor(url: "http://h/:id")
        window.makeKeyAndOrderFront(nil)
        defer { window.orderOut(nil) }
        model.setPathVariable("id", to: "{{tenant}}/{{nope}}")
        editor.render()
        let field = try valueField(editor, row: 0)
        #expect(field.attributedStringValue.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor == theme.color(.variableDefined))
        #expect(field.attributedStringValue.attribute(.wavyUnderline, at: 12, effectiveRange: nil) != nil)

        field.stringValue = ""
        #expect(window.makeFirstResponder(field))
        let fieldEditor = try #require(field.currentEditor() as? NSTextView)
        for character in "{{te" { fieldEditor.insertText(String(character), replacementRange: fieldEditor.selectedRange()) }
        defer { field.suggestions.close() }
        #expect(field.suggestions.isOpen)
        #expect(field.suggestions.items.map(\.name.rawValue) == ["tenant"])
    }
}

/// The user's request, `PUT https://uat-ms-bj-admin-api.sociolabs.io/posts/:id`, shown in a window.
@MainActor
struct PathVariablesClickToEditTests {
    let theme = ThemeEnvironment(catalog: ThemeCatalog.load(), isDark: false)
    let model = TabModel(transport: ScriptedTransport(.failure(.timedOut)), secrets: InMemorySecretStore(), files: DictionaryFileReading([:]), instants: FixedInstantSource(.now), clipboard: RecordingClipboardWriter())
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 700, height: 400), styleMask: [.titled], backing: .buffered, defer: false)

    func shownEditor() -> RequestEditor {
        model.setMethod("PUT")
        model.typeInURLBar("https://uat-ms-bj-admin-api.sociolabs.io/posts/:id")
        let editor = RequestEditor(model: model, theme: theme)
        editor.frame = window.contentView!.bounds
        window.contentView!.addSubview(editor)
        window.makeKeyAndOrderFront(nil)
        editor.layoutSubtreeIfNeeded()
        return editor
    }

    func click(_ table: NSTableView, column: Int) throws -> NSEvent {
        let cell = table.frameOfCell(atColumn: column, row: 0)
        return try #require(NSEvent.mouseEvent(
            with: .leftMouseDown, location: table.convert(NSPoint(x: cell.midX, y: cell.midY), to: nil), modifierFlags: [], timestamp: 0,
            windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1
        ))
    }

    /// A table whose rows cannot be selected is never asked to select one before a click may edit: the
    /// click goes to the field, as AppKit asks the table first (it says no, then selects the row and edits).
    @Test func `a click on the Value cell goes to its field, with no row to select first`() throws {
        let editor = shownEditor()
        defer { window.orderOut(nil) }
        let table = editor.paramsPane.pathTable.table
        let field = try #require((table.view(atColumn: 1, row: 0, makeIfNecessary: true) as? NSTableCellView)?.textField)
        #expect(table.validateProposedFirstResponder(field, for: try click(table, column: 1)))
        #expect(table.selectedRowIndexes.isEmpty)
    }

    @Test func `typing the id into the Value cell and ending the edit sets it and the cell keeps it`() throws {
        let editor = shownEditor()
        defer { window.orderOut(nil) }
        let field = try #require((editor.paramsPane.pathTable.table.view(atColumn: 1, row: 0, makeIfNecessary: true) as? NSTableCellView)?.textField)
        #expect(window.makeFirstResponder(field))
        let fieldEditor = try #require(field.currentEditor() as? NSTextView)
        fieldEditor.insertText("689eba19be47b88f9d590367", replacementRange: fieldEditor.selectedRange())
        editor.render()
        window.makeFirstResponder(nil)
        editor.render()
        #expect(model.tab.definition.pathVariables == ["id": "689eba19be47b88f9d590367"])
        #expect(field.stringValue == "689eba19be47b88f9d590367")
    }

    /// Both labels start at the pane's leading edge, in line with the tables' border.
    @Test func `Query Params and Path Variables are left-aligned over their tables`() {
        let pane = shownEditor().paramsPane
        defer { window.orderOut(nil) }
        for label in [pane.queryLabel, pane.pathLabel] {
            #expect(label.convert(label.alignmentRect(forFrame: label.bounds), to: pane.queryTable).minX == 0)
            #expect(label.alignmentRect(forFrame: label.frame).width == pane.queryTable.frame.width)
        }
    }
}

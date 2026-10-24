import AppKit
@testable import Raccoon
import RaccoonDomain
import RaccoonTesting
import Testing

/// Typing `{{` offers the Variables in scope (design-system §6 Variable suggestions).
@MainActor
struct VariableSuggestionTests {
    let theme = ThemeEnvironment(catalog: ThemeCatalog.load(), isDark: false)
    let panel = VariableSuggestionPanel()

    var kinds: VariableKinds {
        func entry(_ name: String, _ value: VariableEntry.Value) -> VariableEntry { VariableEntry(name: VariableName(name)!, value: value) }
        return VariableKinds(
            active: Environment(name: "Staging", entries: [entry("tenant", .plain("acme"))]),
            globals: Globals(entries: [entry("bearerToken", .secret), entry("host", .plain("httpbin.org"))])
        )
    }

    /// An editable text view with suggestions, focused in a window.
    func makeView(kinds: VariableKinds? = nil) -> (NSWindow, VariableTextView, VariableSuggestions) {
        let view = VariableTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 40))
        view.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        view.allowsUndo = true
        let suggestions = VariableSuggestions(panel: panel, kinds: { [kinds = kinds ?? self.kinds] in kinds }, theme: { [theme] in theme })
        view.suggestions = suggestions
        let window = NSWindow(contentRect: NSRect(x: 200, y: 400, width: 400, height: 40), styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = view
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(view)
        return (window, view, suggestions)
    }

    func type(_ text: String, in view: NSTextView) {
        for character in text { view.insertText(String(character), replacementRange: view.selectedRange()) }
    }

    @Test func `typing {{ opens the list under the caret with every name in scope, the first selected`() throws {
        let (window, view, suggestions) = makeView()
        defer { panel.hide(); window.orderOut(nil) }

        type("Bearer ", in: view)
        #expect(!panel.isShown)
        type("{{", in: view)

        #expect(panel.isShown && suggestions.isOpen)
        #expect(suggestions.items.map(\.name.rawValue) == ["bearerToken", "host", "tenant"])
        #expect(suggestions.items.map(VariableSuggestionPanel.detail) == ["Globals · Secret", "Globals", "Staging"])
        #expect(panel.selected == 0)
        let frame = try #require(panel.frame)
        let caret = view.firstRect(forCharacterRange: NSRange(location: 9, length: 0), actualRange: nil)
        #expect(frame.maxY <= caret.minY && frame.maxY >= caret.minY - 6)
        #expect(frame.width >= 200 && frame.width <= 320)
        #expect(!panel.canBecomeKey)
        #expect(window.firstResponder === view)
    }

    @Test func `typing filters, ↓ moves, and Return writes name}} in one undo step`() {
        let (window, view, suggestions) = makeView()
        defer { panel.hide(); window.orderOut(nil) }
        // No event loop runs here, so the groups one event each would make are made by hand.
        let undo = view.undoManager!
        undo.groupsByEvent = false
        defer { undo.groupsByEvent = true }

        undo.beginUndoGrouping()
        type("Bearer {{e", in: view)
        undo.endUndoGrouping()
        #expect(suggestions.items.map(\.name.rawValue) == ["bearerToken", "tenant"])
        view.doCommand(by: #selector(NSResponder.moveDown(_:)))
        #expect(panel.selected == 1)
        undo.beginUndoGrouping()
        view.doCommand(by: #selector(NSResponder.insertNewline(_:)))
        undo.endUndoGrouping()

        #expect(view.string == "Bearer {{tenant}}")
        #expect(view.selectedRange() == NSRange(location: 17, length: 0))
        #expect(!panel.isShown)
        undo.undo()
        #expect(view.string == "Bearer {{e")
    }

    @Test func `Tab accepts too, and a }} already there is not doubled`() {
        let (window, view, _) = makeView()
        defer { panel.hide(); window.orderOut(nil) }
        view.string = "https://{{}}/x"
        view.setSelectedRange(NSRange(location: 10, length: 0))
        type("h", in: view)

        view.doCommand(by: #selector(NSResponder.insertTab(_:)))

        #expect(view.string == "https://{{host}}/x")
    }

    @Test func `Esc closes the list and nothing else; with no list the keys keep their meaning`() {
        let (window, view, suggestions) = makeView()
        defer { panel.hide(); window.orderOut(nil) }
        type("{{", in: view)

        #expect(suggestions.handle(#selector(NSResponder.cancelOperation(_:)), in: view))
        #expect(!panel.isShown)
        #expect(view.string == "{{")
        #expect(!suggestions.handle(#selector(NSResponder.insertNewline(_:)), in: view))
        #expect(!suggestions.handle(#selector(NSResponder.moveDown(_:)), in: view))
    }

    @Test func `the list closes when the caret leaves, on a character not in a name, and on no match`() {
        let (window, view, _) = makeView()
        defer { panel.hide(); window.orderOut(nil) }

        type("{{ho", in: view)
        #expect(panel.isShown)
        view.setSelectedRange(NSRange(location: 0, length: 0))
        #expect(!panel.isShown)
        // A caret move back into the name does not open it again: only typing does.
        view.setSelectedRange(NSRange(location: 4, length: 0))
        #expect(!panel.isShown)

        type("s", in: view)
        #expect(panel.isShown)
        type(" ", in: view)
        #expect(!panel.isShown)

        type("{{zz", in: view)
        #expect(!panel.isShown)
    }

    @Test func `no Variables in scope, no list`() {
        let (window, view, _) = makeView(kinds: VariableKinds(active: nil, globals: Globals(entries: [])))
        defer { panel.hide(); window.orderOut(nil) }
        type("{{", in: view)
        #expect(!panel.isShown)
    }

    @Test func `losing focus closes the list`() {
        let (window, view, _) = makeView()
        defer { panel.hide(); window.orderOut(nil) }
        type("{{", in: view)

        window.makeFirstResponder(nil)

        #expect(!panel.isShown)
    }

    @Test func `a header cell offers the Globals while it is edited, and the value it keeps is the token`() throws {
        let table = KeyValueTable(theme: theme)
        table.setRows([])
        table.setKinds(kinds)
        let window = NSWindow(contentRect: NSRect(x: 200, y: 400, width: 500, height: 200), styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = table
        window.makeKeyAndOrderFront(nil)
        defer { VariableSuggestionPanel.shared.hide(); window.orderOut(nil) }
        table.layoutSubtreeIfNeeded()
        let cell = try #require((table.table.view(atColumn: 2, row: table.leadRows, makeIfNecessary: true) as? NSTableCellView)?.textField as? VariableField)

        window.makeFirstResponder(cell)
        let editor = try #require(cell.currentEditor() as? VariableTextView)
        type("Bearer {{bea", in: editor)
        #expect(VariableSuggestionPanel.shared.isShown)
        editor.doCommand(by: #selector(NSResponder.insertTab(_:)))

        #expect(editor.string == "Bearer {{bearerToken}}")
    }

    @Test func `the URL field and the raw body offer them too`() throws {
        let urlField = FocusTextField()
        urlField.theme = theme
        urlField.kinds = kinds
        let model = TabModel(transport: ScriptedTransport(.failure(.timedOut)), secrets: InMemorySecretStore(), files: DictionaryFileReading([:]),
                             instants: FixedInstantSource(.now), clipboard: RecordingClipboardWriter())
        let body = BodyPane(model: model, theme: theme)
        body.setBody(.raw(.json, ""), kinds: kinds)
        let window = NSWindow(contentRect: NSRect(x: 200, y: 400, width: 500, height: 300), styleMask: [.titled], backing: .buffered, defer: false)
        let content = NSView(frame: NSRect(x: 0, y: 0, width: 500, height: 300))
        urlField.frame = NSRect(x: 0, y: 270, width: 500, height: 24)
        body.frame = NSRect(x: 0, y: 0, width: 500, height: 260)
        content.addSubview(urlField)
        content.addSubview(body)
        window.contentView = content
        window.makeKeyAndOrderFront(nil)
        defer { VariableSuggestionPanel.shared.hide(); window.orderOut(nil) }

        window.makeFirstResponder(urlField)
        let editor = try #require(urlField.currentEditor() as? VariableTextView)
        type("https://{{", in: editor)
        #expect(VariableSuggestionPanel.shared.isShown)

        window.makeFirstResponder(body.textView)
        #expect(!VariableSuggestionPanel.shared.isShown)
        type("{\"t\": \"{{te", in: body.textView)
        #expect(VariableSuggestionPanel.shared.isShown)
        body.textView.doCommand(by: #selector(NSResponder.insertNewline(_:)))
        #expect(body.textView.string == "{\"t\": \"{{tenant}}")
    }
}

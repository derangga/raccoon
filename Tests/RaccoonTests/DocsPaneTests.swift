import AppKit
@testable import Raccoon
import RaccoonDomain
import RaccoonTesting
import Testing

@MainActor
struct DocsPaneTests {
    let theme = ThemeEnvironment(catalog: ThemeCatalog.load(), isDark: false)
    let model = TabModel(transport: ScriptedTransport(.failure(.timedOut(seconds: 60))), secrets: InMemorySecretStore(), files: DictionaryFileReading([:]), instants: FixedInstantSource(.now), clipboard: RecordingClipboardWriter())
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 700, height: 400), styleMask: [.titled], backing: .buffered, defer: false)

    /// An editor on a saved Request, so edits are Dirty against its baseline.
    func editor() -> RequestEditor {
        model.tab = Tab(id: model.tab.id, source: .request(RequestID(UUID())), definition: .empty, baseline: .empty)
        let editor = RequestEditor(model: model, theme: theme)
        editor.frame = window.contentView!.bounds
        window.contentView!.addSubview(editor)
        editor.layoutSubtreeIfNeeded()
        return editor
    }

    @Test func `Docs is the leftmost section, and a Request still opens on Params`() {
        let editor = editor()
        #expect(EditorSection.allCases.first == .docs)
        #expect(editor.selected == .params)
        #expect(editor.docsPane.isHiddenOrHasHiddenAncestor)
        editor.select(.docs)
        #expect(!editor.docsPane.isHiddenOrHasHiddenAncestor)
    }

    @Test func `Docs shows a dot once it has text, and no count`() {
        let editor = editor()
        let button = editor.sectionButton(.docs)
        #expect(!button.hasDot)
        model.tab.definition.docs = "x"
        editor.render()
        #expect(button.hasDot && button.accessibilityLabel() == "Docs")
        model.tab.definition.docs = ""
        editor.render()
        #expect(!button.hasDot)
    }

    @Test func `typing in Docs writes the definition and makes the Tab Dirty, and Undo makes it clean`() throws {
        let editor = editor()
        editor.select(.docs)
        let text = editor.docsPane.textView
        window.contentView?.addSubview(editor)
        #expect(window.makeFirstResponder(text))
        #expect(!model.tab.isDirty)

        text.insertText("# Charges", replacementRange: NSRange(location: 0, length: 0))
        #expect(model.tab.definition.docs == "# Charges")
        #expect(model.tab.isDirty)

        try #require(text.undoManager).undo()
        #expect(model.tab.definition.docs == "")
        #expect(!model.tab.isDirty)
    }

    @Test func `text from outside replaces the editor's, and the user's own typing is left alone`() {
        let editor = editor()
        model.tab.definition.docs = "from disk"
        editor.render()
        #expect(editor.docsPane.textView.string == "from disk")
        editor.docsPane.textView.setSelectedRange(NSRange(location: 4, length: 0))
        editor.render()
        #expect(editor.docsPane.textView.selectedRange().location == 4)
    }

    @Test func `markdown is styled in place and the characters never change`() throws {
        let editor = editor()
        let text = "# Title\n**b** `c` [d](https://a.io)\n- x {{name}}"
        model.tab.definition.docs = text
        editor.render()
        let storage = try #require(editor.docsPane.textView.textStorage)
        #expect(storage.string == text)
        func attribute<T>(_ key: NSAttributedString.Key, at index: Int) -> T? { storage.attribute(key, at: index, effectiveRange: nil) as? T }
        func font(at index: Int) -> NSFont { storage.attribute(.font, at: index, effectiveRange: nil) as! NSFont }
        func weight(at index: Int) -> Int { NSFontManager.shared.weight(of: font(at: index)) }
        // `#` is a dimmed mark, the heading text is 20 pt semibold
        #expect(attribute(.foregroundColor, at: 0) == theme.color(.textTertiary))
        #expect(font(at: 2).pointSize == 20)
        let semibold = NSFontManager.shared.weight(of: .systemFont(ofSize: 13, weight: .semibold))
        #expect(weight(at: 2) == semibold)
        // `**` stays, dimmed; the bold text is semibold, heavier than the body text after it
        #expect(attribute(.foregroundColor, at: 8) == theme.color(.textTertiary))
        #expect(weight(at: 10) == semibold && weight(at: 13) < semibold && font(at: 10).pointSize == 13)
        // inline code is a monospaced font on the recessed background
        #expect(font(at: 15).isFixedPitch)
        #expect(attribute(.backgroundColor, at: 15) == theme.color(.backgroundRecessed))
        // a link is accent and carries its URL; {{name}} is plain text
        #expect(attribute(.link, at: 19) == URL(string: "https://a.io"))
        let braces = (text as NSString).range(of: "{{name}}").location
        #expect(attribute(.foregroundColor, at: braces) == theme.color(.text))
        #expect(attribute(.link, at: braces) as URL? == nil)
    }

    @Test func `a Variable in Docs is not an Undefined Variable`() {
        var definition = RequestDefinition.empty
        definition.docs = "Send {{nope}}"
        let kinds = VariableKinds(active: nil, globals: Globals(entries: []))
        #expect(!EditorSection.docs.holdsUndefined(in: definition, kinds: kinds))
    }
}

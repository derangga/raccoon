import AppKit
@testable import Raccoon
import RaccoonDomain
import RaccoonTesting
import Testing

/// The Docs editor's hidden marks, format commands and toolbar (docs.md).
@MainActor
struct DocsEditorTests {
    let theme = ThemeEnvironment(catalog: ThemeCatalog.load(), isDark: false)
    let model = TabModel(transport: ScriptedTransport(.failure(.timedOut(seconds: 60))), secrets: InMemorySecretStore(), files: DictionaryFileReading([:]), instants: FixedInstantSource(.now), clipboard: RecordingClipboardWriter())
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 700, height: 400), styleMask: [.titled], backing: .buffered, defer: false)

    /// The Docs editor on a saved Request holding `docs`, first responder.
    func focused(_ docs: String = "") -> (pane: DocsPane, text: DocsTextView) {
        model.tab = Tab(id: model.tab.id, source: .request(RequestID(UUID())), definition: .empty, baseline: .empty)
        let editor = RequestEditor(model: model, theme: theme)
        editor.frame = window.contentView!.bounds
        window.contentView!.addSubview(editor)
        editor.layoutSubtreeIfNeeded()
        editor.select(.docs)
        model.tab.definition.docs = docs
        model.tab.baseline?.docs = docs
        editor.render()
        _ = window.makeFirstResponder(editor.docsPane.textView)
        return (editor.docsPane, editor.docsPane.textView)
    }

    func item(_ format: DocsFormat) -> NSMenuItem { format.menuItem() }

    func glyphProperty(_ text: DocsTextView, at index: Int) -> NSLayoutManager.GlyphProperty {
        let layout = text.layoutManager!
        layout.ensureGlyphs(forCharacterRange: NSRange(location: 0, length: text.string.utf16.count))
        return layout.propertyForGlyph(at: layout.glyphIndexForCharacter(at: index))
    }

    // MARK: hidden marks

    @Test func `matched marks draw no glyphs, an unmatched one shows, and the storage is the markdown`() {
        let (_, text) = focused("## Title\n**b** and **c")
        #expect(text.string == "## Title\n**b** and **c")
        for index in 0...2 { #expect(glyphProperty(text, at: index).contains(.null)) }
        #expect(!glyphProperty(text, at: 3).contains(.null))
        #expect(glyphProperty(text, at: 9).contains(.null) && glyphProperty(text, at: 10).contains(.null))
        #expect(!glyphProperty(text, at: 11).contains(.null) && glyphProperty(text, at: 12).contains(.null))
        // `**c` has no closing mark: shown as text
        #expect(!glyphProperty(text, at: 20).contains(.null))
    }

    @Test func `a quote's mark and space are hidden, its line is indented and a fence line stays`() throws {
        let (_, text) = focused("> q\n```\nx\n```")
        #expect(glyphProperty(text, at: 0).contains(.null) && glyphProperty(text, at: 1).contains(.null))
        let indent = try #require(text.textStorage?.attribute(.paragraphStyle, at: 2, effectiveRange: nil) as? NSParagraphStyle)
        #expect(indent.firstLineHeadIndent == 12 && indent.headIndent == 12)
        #expect(text.quoteLines == [NSRange(location: 0, length: 4)])
        #expect(!glyphProperty(text, at: 4).contains(.null))
    }

    @Test func `a list's dash is drawn as a bullet`() throws {
        let (_, text) = focused("- x\n1. y")
        let layout = try #require(text.layoutManager)
        layout.ensureGlyphs(forCharacterRange: NSRange(location: 0, length: 8))
        var dot: UniChar = 0x2022, bullet = CGGlyph()
        CTFontGetGlyphsForCharacters(try #require(text.textStorage?.attribute(.font, at: 0, effectiveRange: nil) as? NSFont), &dot, &bullet, 1)
        #expect(layout.cgGlyph(at: 0) == bullet && bullet != 0)
        #expect(text.string == "- x\n1. y")
        // a numbered item keeps its number
        #expect(layout.cgGlyph(at: 4) != bullet)
    }

    @Test func `strikethrough is single, and a link's URL is its tooltip`() throws {
        let (_, text) = focused("~~s~~ [l](https://a.io)")
        let storage = try #require(text.textStorage)
        #expect(storage.attribute(.strikethroughStyle, at: 2, effectiveRange: nil) as? Int == NSUnderlineStyle.single.rawValue)
        #expect(storage.attribute(.toolTip, at: 7, effectiveRange: nil) as? String == "https://a.io")
    }

    @Test func `the caret never rests inside a hidden mark, and moves in its direction of travel`() {
        let (_, text) = focused("**bold**")
        // from the left of `**`: forward to after it
        text.setSelectedRange(NSRange(location: 0, length: 0))
        text.setSelectedRange(NSRange(location: 1, length: 0))
        #expect(text.selectedRange() == NSRange(location: 2, length: 0))
        // from the right: back to before the closing `**`
        text.setSelectedRange(NSRange(location: 8, length: 0))
        text.setSelectedRange(NSRange(location: 7, length: 0))
        #expect(text.selectedRange() == NSRange(location: 6, length: 0))
        // a selection that spans marks is not moved
        text.setSelectedRange(NSRange(location: 0, length: 8))
        #expect(text.selectedRange() == NSRange(location: 0, length: 8))
    }

    @Test func `typing at the start of a styled line does not push the caret out`() {
        let (_, text) = focused("**b**")
        text.setSelectedRange(NSRange(location: 0, length: 0))
        text.insertText("x", replacementRange: NSRange(location: 0, length: 0))
        #expect(text.string == "x**b**" && text.selectedRange() == NSRange(location: 1, length: 0))
    }

    @Test func `Home, Left and a click never leave the caret before a heading's mark`() {
        let (_, text) = focused("a\n## T")
        text.setSelectedRange(NSRange(location: 6, length: 0))
        text.moveToBeginningOfLine(nil)
        #expect(text.selectedRange() == NSRange(location: 5, length: 0))
        // Left from just after the mark goes to the end of the previous line
        text.moveLeft(nil)
        #expect(text.selectedRange() == NSRange(location: 1, length: 0))
        // Right goes over the mark
        text.moveRight(nil)
        #expect(text.selectedRange() == NSRange(location: 5, length: 0))
        // a click at the line's very start
        text.setSelectedRange(NSRange(location: 2, length: 0))
        #expect(text.selectedRange() == NSRange(location: 5, length: 0))
        // typing there does not break the heading, and Delete there joins nothing
        text.insertText("x", replacementRange: NSRange(location: 5, length: 0))
        #expect(text.string == "a\n## xT")
    }

    @Test func `at the first line a heading's caret stays after the mark`() {
        let (_, text) = focused("## T")
        text.setSelectedRange(NSRange(location: 4, length: 0))
        text.moveToBeginningOfLine(nil)
        #expect(text.selectedRange() == NSRange(location: 3, length: 0))
        text.moveLeft(nil)
        #expect(text.selectedRange() == NSRange(location: 3, length: 0))
        text.insertText("x", replacementRange: NSRange(location: 3, length: 0))
        #expect(text.string == "## xT")
    }

    @Test func `neither end of a selection rests inside a hidden mark`() {
        let (_, text) = focused("**bold**")
        text.setSelectedRange(NSRange(location: 0, length: 0))
        text.setSelectedRange(NSRange(location: 3, length: 4))
        #expect(text.selectedRange() == NSRange(location: 3, length: 5))
        text.setSelectedRange(NSRange(location: 3, length: 4))
        #expect(text.selectedRange() == NSRange(location: 3, length: 3))
    }

    @Test func `new characters get glyphs while the hidden indexes are the old text's`() {
        let (_, text) = focused("**b**")
        text.textStorage?.replaceCharacters(in: NSRange(location: 0, length: 0), with: "xyz")
        let layout = text.layoutManager!
        layout.invalidateGlyphs(forCharacterRange: NSRange(location: 0, length: 8), changeInLength: 0, actualCharacterRange: nil)
        for index in 0..<8 { #expect(!glyphProperty(text, at: index).contains(.null)) }
    }

    // MARK: commands

    @Test func `Bold wraps the selection as one undo step and makes the Tab Dirty`() throws {
        let (_, text) = focused("word")
        text.setSelectedRange(NSRange(location: 0, length: 4))
        text.applyFormat(item(.bold))
        #expect(text.string == "**word**" && model.tab.definition.docs == "**word**")
        #expect(model.tab.isDirty)
        let undo = try #require(text.undoManager)
        #expect(undo.undoActionName == "Bold" && undo.undoMenuItemTitle == "Undo Bold")
        undo.undo()
        #expect(text.string == "word" && model.tab.definition.docs == "word" && !model.tab.isDirty)
    }

    @Test func `a block command sets the caret's line, and the toolbar buttons follow the caret`() {
        let (pane, text) = focused("title\n**b**")
        text.setSelectedRange(NSRange(location: 2, length: 0))
        text.applyFormat(item(.heading2))
        #expect(text.string == "## title\n**b**")
        #expect(pane.toolbar.styleTitle == "Heading 2")
        text.setSelectedRange(NSRange(location: 11, length: 1))
        #expect(pane.toolbar.buttons[.bold]?.isOn == true && pane.toolbar.buttons[.italic]?.isOn == false)
        #expect(pane.toolbar.styleTitle == "Normal text")
    }

    @Test func `Return continues a list and ends it on an empty item`() {
        let (_, text) = focused("- a")
        text.setSelectedRange(NSRange(location: 3, length: 0))
        text.insertNewline(nil)
        #expect(text.string == "- a\n- ")
        text.insertNewline(nil)
        #expect(text.string == "- a\n")
        // a plain line: DocsEdit declines and the editor inserts its own line break
        text.insertNewline(nil)
        #expect(text.string == "- a\n\n" && model.tab.definition.docs == "- a\n\n")
    }

    @Test func `Delete at a line start removes its mark and otherwise deletes`() {
        let (_, text) = focused("## T")
        text.setSelectedRange(NSRange(location: 3, length: 0))
        text.deleteBackward(nil)
        #expect(text.string == "T")
        text.setSelectedRange(NSRange(location: 1, length: 0))
        text.deleteBackward(nil)
        #expect(text.string == "")
    }

    @Test func `a command replaces only the span that changed, and undo restores it`() throws {
        let (_, text) = focused("a b c")
        text.setSelectedRange(NSRange(location: 2, length: 0))
        let recorder = EditRecorder()
        text.textStorage?.delegate = recorder
        defer { text.textStorage?.delegate = nil }
        let edits = { recorder.edits }
        text.applyFormat(item(.bold))
        #expect(text.string == "a **b** c")
        #expect(edits().count == 1 && edits()[0].0 == NSRange(location: 2, length: 5) && edits()[0].1 == 4)
        try #require(text.undoManager).undo()
        #expect(text.string == "a b c" && text.selectedRange().length <= 1)
    }

    @Test func `Delete right after hidden marks removes the visible character, and the marks when it was the last`() {
        let (_, text) = focused("**bc**")
        text.setSelectedRange(NSRange(location: 6, length: 0))
        text.deleteBackward(nil)
        #expect(text.string == "**b**" && text.selectedRange() == NSRange(location: 5, length: 0))
        text.deleteBackward(nil)
        #expect(text.string == "" && model.tab.definition.docs == "")
        // a link goes whole with its URL
        let (_, link) = focused("x [b](https://a.io)")
        link.setSelectedRange(NSRange(location: 19, length: 0))
        link.deleteBackward(nil)
        #expect(link.string == "x ")
        // right after the opening marks, Delete joins the line above
        let (_, lines) = focused("a\n**b**")
        lines.setSelectedRange(NSRange(location: 4, length: 0))
        lines.deleteBackward(nil)
        #expect(lines.string == "a**b**")
    }

    @Test func `Delete does not split an emoji, and takes marks one at a time`() {
        let (_, emoji) = focused("**😀**")
        emoji.setSelectedRange(NSRange(location: 6, length: 0))
        emoji.deleteBackward(nil)
        #expect(emoji.string == "")
        // two spans side by side: only the one before the caret goes
        let (_, spans) = focused("**a**~~b~~")
        spans.setSelectedRange(NSRange(location: 10, length: 0))
        spans.deleteBackward(nil)
        #expect(spans.string == "**a**" && spans.selectedRange() == NSRange(location: 5, length: 0))
        // after a span's closing marks, with a heading mark before it
        let (_, heading) = focused("## **b**")
        heading.setSelectedRange(NSRange(location: 8, length: 0))
        heading.deleteBackward(nil)
        #expect(heading.string == "## ")
        // right after the opening marks of the span before it
        let (_, adjacent) = focused("**a**~~b~~")
        adjacent.setSelectedRange(NSRange(location: 7, length: 0))
        adjacent.deleteBackward(nil)
        #expect(adjacent.string == "~~b~~" && adjacent.selectedRange() == NSRange(location: 2, length: 0))
    }

    @Test func `Delete after a quote's line mark and the span's opening marks removes the line mark`() {
        let (_, text) = focused("> **b**")
        text.setSelectedRange(NSRange(location: 4, length: 0))
        text.deleteBackward(nil)
        #expect(text.string == "**b**" && text.selectedRange() == NSRange(location: 2, length: 0))
    }

    @Test func `a restyle settles a caret that rests inside a new mark`() {
        let (pane, text) = focused("[b](https://a.io)")
        // the text moved on without a restyle (as after an undo): the caret is where the marks were not
        text.markedUpText = ""
        text.setSelectedRange(NSRange(location: 14, length: 0))
        #expect(text.selectedRange().location == 14)
        pane.textDidChange(Notification(name: NSText.didChangeNotification))
        #expect(text.selectedRange() == NSRange(location: 17, length: 0))
        let (heading, line) = focused("## T")
        line.markedUpText = ""
        line.setSelectedRange(NSRange(location: 1, length: 0))
        heading.textDidChange(Notification(name: NSText.didChangeNotification))
        #expect(line.selectedRange() == NSRange(location: 3, length: 0))
    }

    @Test func `a held inset is released once the mouse button is up`() async throws {
        let (pane, text) = focused("x")
        _ = window.makeFirstResponder(nil)
        text.holdInsetForClick()
        _ = window.makeFirstResponder(text)
        #expect(text.textContainerInset.height == 16)
        try await Task.sleep(for: .milliseconds(400))
        #expect(!text.isPlacingClick && text.textContainerInset.height == 56 && !pane.toolbar.isHidden)
    }

    // MARK: toolbar

    @Test func `the toolbar shows while the editor is first responder, and Esc hides it`() {
        let (pane, text) = focused("x")
        #expect(!pane.toolbar.isHidden)
        #expect(text.textContainerInset.height == 56)
        text.cancelOperation(nil)
        #expect(window.firstResponder !== text)
        #expect(pane.toolbar.isHidden && text.textContainerInset.height == 16)
        #expect(window.makeFirstResponder(text))
        #expect(!pane.toolbar.isHidden)
        #expect(window.makeFirstResponder(nil))
        #expect(pane.toolbar.isHidden)
    }

    @Test func `a toolbar click acts on the editor and leaves it first responder`() {
        let (pane, text) = focused("word")
        text.setSelectedRange(NSRange(location: 0, length: 4))
        let button = pane.toolbar.buttons[.italic]!
        #expect(!button.acceptsFirstResponder && button.refusesFirstResponder)
        button.performClick(nil)
        #expect(text.string == "*word*" && window.firstResponder === text && !pane.toolbar.isHidden)
        #expect(button.toolTip == "Italic (⌘I)" && button.accessibilityLabel() == "Italic (⌘I)")
    }

    @Test func `a click that focuses the editor keeps the text still until it is placed`() {
        let (pane, text) = focused("line one\nline two")
        _ = window.makeFirstResponder(nil)
        #expect(pane.toolbar.isHidden && text.textContainerInset.height == 16)
        // What the window does for a click on the unfocused editor: focus it, then deliver mouseDown.
        text.holdInsetForClick()
        _ = window.makeFirstResponder(text)
        #expect(!pane.toolbar.isHidden && text.textContainerInset.height == 16)
        text.endClick()
        #expect(text.textContainerInset.height == 56)
        // a focus that is not a click moves the text at once
        _ = window.makeFirstResponder(nil)
        _ = window.makeFirstResponder(text)
        #expect(text.textContainerInset.height == 56)
    }

    // MARK: link popover

    @Test func `Link asks for the URL, prefilled, and Return applies it`() throws {
        let (_, text) = focused("see")
        text.setSelectedRange(NSRange(location: 0, length: 3))
        text.applyFormat(item(.link))
        defer { text.linkPopover?.close() }
        let controller = try #require(text.linkPopover?.contentViewController as? LinkPopoverController)
        _ = controller.view
        #expect(controller.field.stringValue == "https://")
        controller.field.stringValue = "https://a.io"
        #expect(controller.control(controller.field, textView: NSTextView(), doCommandBy: #selector(NSResponder.insertNewline(_:))))
        #expect(text.string == "[see](https://a.io)" && model.tab.isDirty)
    }

    @Test func `Link in a link is prefilled with its URL, and Esc cancels`() throws {
        let (_, text) = focused("[see](https://a.io)")
        text.setSelectedRange(NSRange(location: 2, length: 0))
        text.applyFormat(item(.link))
        defer { text.linkPopover?.close() }
        let controller = try #require(text.linkPopover?.contentViewController as? LinkPopoverController)
        _ = controller.view
        #expect(controller.field.stringValue == "https://a.io")
        controller.field.stringValue = "https://b.io"
        #expect(controller.control(controller.field, textView: NSTextView(), doCommandBy: #selector(NSResponder.cancelOperation(_:))))
        #expect(text.string == "[see](https://a.io)" && !model.tab.isDirty)
    }

    // MARK: Format menu

    @Test func `the Format menu sits between Edit and View with the same items in the same groups`() throws {
        let menu = MainMenu.make(theme: ThemeController(defaults: .standard, catalog: ThemeCatalog.load(), appearanceSource: NSView()))
        let titles = menu.items.map(\.title)
        let format = try #require(menu.item(withTitle: "Format")?.submenu)
        #expect(titles.firstIndex(of: "Format") == titles.firstIndex(of: "Edit")! + 1 && titles.firstIndex(of: "View") == titles.firstIndex(of: "Format")! + 1)
        let groups = format.items.split(whereSeparator: \.isSeparatorItem).map { $0.map { "\($0.title) \(DocsFormat(rawValue: $0.tag)!.shortcut)" } }
        #expect(groups == [
            ["Normal text ⌥⌘0", "Heading 1 ⌥⌘1", "Heading 2 ⌥⌘2", "Heading 3 ⌥⌘3"],
            ["Bold ⌘B", "Italic ⌘I", "Strikethrough ⇧⌘X"],
            ["Bulleted list ⇧⌘8", "Numbered list ⇧⌘7"],
            ["Link… ⌘K", "Quote ⇧⌘9", "Inline code ⌘E", "Code block ⌥⌘C"],
        ])
        // only the Docs editor takes them: the items have no target and the action is nobody else's
        #expect(format.items.filter { !$0.isSeparatorItem }.allSatisfy { $0.target == nil && $0.action == #selector(DocsTextView.applyFormat(_:)) })
        #expect(!NSTextView().responds(to: #selector(DocsTextView.applyFormat(_:))))
    }

    @Test func `no shortcut in the menu bar is claimed twice`() {
        let menu = MainMenu.make(theme: ThemeController(defaults: .standard, catalog: ThemeCatalog.load(), appearanceSource: NSView()))
        func shortcuts(_ menu: NSMenu) -> [String] {
            menu.items.flatMap { item -> [String] in
                (item.keyEquivalent.isEmpty ? [] : ["\(item.keyEquivalentModifierMask.intersection(.deviceIndependentFlagsMask).rawValue) \(item.keyEquivalent)"])
                    + (item.submenu.map(shortcuts) ?? [])
            }
        }
        let all = shortcuts(menu)
        #expect(Set(all).count == all.count)
    }
}

/// The character edits a text storage processed: the edited range and the change in length.
private final class EditRecorder: NSObject, NSTextStorageDelegate {
    var edits: [(NSRange, Int)] = []

    func textStorage(_ textStorage: NSTextStorage, didProcessEditing editedMask: NSTextStorageEditActions, range editedRange: NSRange, changeInLength delta: Int) {
        if editedMask.contains(.editedCharacters) { edits.append((editedRange, delta)) }
    }
}

import AppKit
@testable import Raccoon
import RaccoonDomain
import RaccoonTesting
import Testing

/// The `:name` token in the URL field (design-system §6 URL bar): paint only.
@MainActor
struct PathTokenTests {
    let theme = ThemeEnvironment(catalog: ThemeCatalog.load(), isDark: false)
    let model = TabModel(transport: ScriptedTransport(.failure(.timedOut)), secrets: InMemorySecretStore(), files: DictionaryFileReading([:]), instants: FixedInstantSource(.now), clipboard: RecordingClipboardWriter())
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 700, height: 120), styleMask: [.titled], backing: .buffered, defer: false)

    func bar() -> URLBar {
        let bar = URLBar(model: model, theme: theme)
        bar.frame = window.contentView!.bounds
        window.contentView!.addSubview(bar)
        bar.layoutSubtreeIfNeeded()
        return bar
    }

    /// The ranges carrying the token attribute, in order.
    func tokenRanges(_ text: NSAttributedString) -> [NSRange] {
        var ranges: [NSRange] = []
        text.enumerateAttribute(.pathToken, in: NSRange(location: 0, length: text.length)) { value, range, _ in
            if value != nil { ranges.append(range) }
        }
        return ranges
    }

    @Test(arguments: [
        ("http://localhost:3061/posts", [NSRange]()),
        ("http://localhost:3061/posts/:id/retry", [NSRange(location: 28, length: 3)]),
        ("/:a/x/:b", [NSRange(location: 1, length: 2), NSRange(location: 6, length: 2)]),
        ("http://h/{{x}}/:id", [NSRange(location: 15, length: 3)]),
    ])
    func `each :name is marked, and no part of a URL that has none`(url: String, expected: [NSRange]) {
        let kinds = VariableKinds(active: nil, globals: Globals(entries: []))
        let text = NSMutableAttributedString(string: url, attributes: [.foregroundColor: theme.color(.text)])
        VariableStyle.apply(kinds, to: text, disabled: false, theme: theme, pathTokens: true)
        #expect(tokenRanges(text) == expected)
        for range in expected {
            #expect(text.attribute(.foregroundColor, at: range.location, effectiveRange: nil) as? NSColor == theme.color(.textSecondary))
        }
        #expect(text.string == url)
    }

    @Test func `a field that does not take tokens marks none`() {
        let text = NSMutableAttributedString(string: "/:id")
        VariableStyle.apply(VariableKinds(active: nil, globals: Globals(entries: [])), to: text, disabled: false, theme: theme)
        #expect(tokenRanges(text) == [])
    }

    @Test func `the URL field follows the text on every edit`() {
        let bar = bar()
        model.typeInURLBar("http://localhost:3061/posts/:id/retry")
        bar.render()
        #expect(tokenRanges(bar.urlField.attributedStringValue) == [NSRange(location: 28, length: 3)])

        model.typeInURLBar("http://localhost:3061/posts/:identity/retry")
        bar.render()
        #expect(tokenRanges(bar.urlField.attributedStringValue) == [NSRange(location: 28, length: 9)])

        model.typeInURLBar("http://localhost:3061/posts")
        bar.render()
        #expect(tokenRanges(bar.urlField.attributedStringValue) == [])
    }

    @Test func `the token is the editor's too, and typing in and next to it changes only the text`() throws {
        let bar = bar()
        model.typeInURLBar("http://h/:id/x")
        bar.render()
        window.makeKeyAndOrderFront(nil)
        defer { window.orderOut(nil) }
        window.makeFirstResponder(bar.urlField)
        let editor = try #require(bar.urlField.currentEditor() as? NSTextView)
        bar.urlField.highlight()
        let storage = try #require(editor.textStorage)
        #expect(tokenRanges(storage) == [NSRange(location: 9, length: 3)])

        // Inside the name: the caret lands one past the typed character, the text is as typed.
        editor.setSelectedRange(NSRange(location: 11, length: 0))
        editor.insertText("Z", replacementRange: editor.selectedRange())
        #expect(editor.string == "http://h/:iZd/x")
        #expect(editor.selectedRange() == NSRange(location: 12, length: 0))
        bar.urlField.highlight()
        #expect(tokenRanges(storage) == [NSRange(location: 9, length: 4)])

        // Right after the name, and right before the colon.
        editor.setSelectedRange(NSRange(location: 13, length: 0))
        editor.insertText("!", replacementRange: editor.selectedRange())
        #expect(editor.string == "http://h/:iZd!/x" && editor.selectedRange() == NSRange(location: 14, length: 0))
        editor.setSelectedRange(NSRange(location: 9, length: 0))
        editor.insertText("a", replacementRange: editor.selectedRange())
        #expect(editor.string == "http://h/a:iZd!/x" && editor.selectedRange() == NSRange(location: 10, length: 0))
    }

    @Test func `selecting across a token and copying gives the plain text`() throws {
        let bar = bar()
        model.typeInURLBar("http://h/:id/x")
        bar.render()
        window.makeKeyAndOrderFront(nil)
        defer { window.orderOut(nil) }
        window.makeFirstResponder(bar.urlField)
        let editor = try #require(bar.urlField.currentEditor() as? NSTextView)
        bar.urlField.highlight()
        editor.setSelectedRange(NSRange(location: 5, length: 8))
        let board = NSPasteboard.general
        let before = board.string(forType: .string)
        defer { board.clearContents(); if let before { board.setString(before, forType: .string) } }
        editor.copy(nil)
        #expect(board.string(forType: .string) == "//h/:id/")
    }

    @Test func `at rest the token is drawn under the text in backgroundRecessed with a hairline, and only on :id`() throws {
        let bar = bar()
        model.typeInURLBar("http://localhost:3061/posts/:id/retry")
        bar.render()
        let underlay = try #require(bar.urlBox.subviews.first { $0 is PathTokenUnderlay })
        #expect(!underlay.isHidden)
        #expect(bar.urlBox.subviews.firstIndex(of: underlay)! < bar.urlBox.subviews.firstIndex(of: bar.urlField)!)

        let layout = try #require((underlay as? PathTokenUnderlay)?.layout)
        let manager = layout.manager
        let range = NSRange(location: 28, length: 3)
        let rect = manager.boundingRect(forGlyphRange: manager.glyphRange(forCharacterRange: range, actualCharacterRange: nil), in: manager.textContainers[0])
        let inside = NSPoint(x: layout.origin.x + rect.midX, y: layout.origin.y + rect.midY)
        let outside = NSPoint(x: layout.origin.x + 10, y: layout.origin.y + rect.midY)

        let image = try #require(underlay.bitmapImageRepForCachingDisplay(in: underlay.bounds))
        underlay.cacheDisplay(in: underlay.bounds, to: image)
        let scale = CGFloat(image.pixelsWide) / underlay.bounds.width
        func pixel(_ point: NSPoint) -> NSColor? {
            image.colorAt(x: Int(point.x * scale), y: Int(point.y * scale))?.usingColorSpace(.sRGB)
        }
        let recessed = try #require(theme.color(.backgroundRecessed).usingColorSpace(.sRGB))
        let got = try #require(pixel(inside))
        // The bitmap's colour space shifts a channel by up to 0.02; any other fill is further off.
        #expect(abs(got.redComponent - recessed.redComponent) < 0.03 && abs(got.greenComponent - recessed.greenComponent) < 0.03)
        #expect(pixel(outside)?.alphaComponent == 0)
    }

    @Test func `the underlay steps aside while the field is edited`() {
        let bar = bar()
        model.typeInURLBar("/:id")
        bar.render()
        window.makeKeyAndOrderFront(nil)
        defer { window.orderOut(nil) }
        window.makeFirstResponder(bar.urlField)
        #expect(bar.urlBox.subviews.first { $0 is PathTokenUnderlay }?.isHidden == true)
        window.makeFirstResponder(nil)
        #expect(tokenRanges(bar.urlField.attributedStringValue) == [NSRange(location: 1, length: 3)])
        #expect(bar.urlBox.subviews.first { $0 is PathTokenUnderlay }?.isHidden == false)
    }
}

/// Undo and Redo of a URL edit that prunes a Path Variable value (editing.md §typeInURLBar).
@MainActor
struct PathVariableUndoTests {
    let theme = ThemeEnvironment(catalog: ThemeCatalog.load(), isDark: false)
    let model = TabModel(transport: ScriptedTransport(.failure(.timedOut)), secrets: InMemorySecretStore(), files: DictionaryFileReading([:]), instants: FixedInstantSource(.now), clipboard: RecordingClipboardWriter())
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 700, height: 120), styleMask: [.titled], backing: .buffered, defer: false)

    @Test func `Undo after deleting :id brings :id back with its value, and Redo takes both away again`() throws {
        let bar = URLBar(model: model, theme: theme)
        bar.frame = window.contentView!.bounds
        window.contentView!.addSubview(bar)
        bar.layoutSubtreeIfNeeded()
        model.typeInURLBar("http://h/:id/x")
        model.setPathVariable("id", to: "7")
        bar.render()
        window.makeKeyAndOrderFront(nil)
        defer { window.orderOut(nil) }
        let editor = try #require(bar.urlField.currentEditor() as? NSTextView)
        let undo = try #require(editor.undoManager)
        undo.groupsByEvent = false

        undo.beginUndoGrouping()
        editor.setSelectedRange(NSRange(location: 9, length: 3))
        editor.insertText("", replacementRange: editor.selectedRange())
        bar.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: bar.urlField))
        undo.endUndoGrouping()
        #expect(model.tab.definition.url == "http://h//x" && model.tab.definition.pathVariables == [:])

        undo.undo()
        bar.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: bar.urlField))
        #expect(editor.string == "http://h/:id/x")
        #expect(model.tab.definition.url == "http://h/:id/x" && model.tab.definition.pathVariables == ["id": "7"])

        undo.redo()
        bar.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: bar.urlField))
        #expect(model.tab.definition.url == "http://h//x" && model.tab.definition.pathVariables == [:])
    }
}

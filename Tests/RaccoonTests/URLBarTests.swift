import AppKit
@testable import Raccoon
import RaccoonDomain
import RaccoonTesting
import Testing

@MainActor
struct URLBarTests {
    let theme = ThemeEnvironment(catalog: ThemeCatalog.load(), isDark: false)
    let model = TabModel(transport: ScriptedTransport(.failure(.timedOut)), secrets: InMemorySecretStore(), files: DictionaryFileReading([:]), instants: FixedInstantSource(.now))
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 700, height: 120), styleMask: [], backing: .buffered, defer: false)

    func bar() -> URLBar {
        let bar = URLBar(model: model, theme: theme)
        bar.frame = window.contentView!.bounds
        window.contentView!.addSubview(bar)
        bar.layoutSubtreeIfNeeded()
        return bar
    }

    @Test func `the empty Draft shows GET, the placeholder and Send`() {
        let bar = bar()
        #expect(bar.methodButton.attributedTitle.string.hasPrefix("GET"))
        #expect(bar.urlField.stringValue == "")
        #expect(bar.urlField.placeholderAttributedString?.string == "Enter a URL, or paste a curl command")
        #expect(bar.sendButton.attributedTitle.string == "Send")
        #expect(bar.sendButton.keyEquivalent == "\r" && bar.sendButton.keyEquivalentModifierMask == .command)
        #expect(bar.messageLine.isHidden)
    }

    @Test func `while sending, Send becomes Cancel on ⌘. and cancelling restores Send on ⌘↩`() async {
        let bar = bar()
        model.tab.definition.url = "http://localhost/"
        model.send()
        let send = model.inFlight
        bar.render()
        #expect(bar.sendButton.attributedTitle.string == "Cancel")
        #expect(bar.sendButton.keyEquivalent == "." && bar.sendButton.keyEquivalentModifierMask == .command)
        #expect(bar.sendButton.toolTip == "Cancel (⌘.)")
        #expect(bar.sendButton.layer?.backgroundColor == theme.color(.backgroundElevated).cgColor)
        #expect(bar.sendButton.layer?.borderColor == theme.color(.border).cgColor)
        #expect(bar.sendButton.attributedTitle.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor == theme.color(.text))

        bar.sendButton.performClick(nil)
        await send?.value
        bar.render()

        #expect(model.tab.response == .idle)
        #expect(bar.sendButton.attributedTitle.string == "Send")
        #expect(bar.sendButton.keyEquivalent == "\r" && bar.sendButton.keyEquivalentModifierMask == .command)
        #expect(bar.sendButton.layer?.backgroundColor == theme.color(.accent).cgColor)
    }

    @Test func `an invalid URL outlines the field in error until the next edit`() {
        let bar = bar()
        model.tab.definition.url = "not a url"
        model.send()
        bar.render()
        #expect(bar.urlBox.layer?.borderColor == theme.color(.error).cgColor)

        bar.urlField.stringValue = "http://localhost/"
        bar.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: bar.urlField))
        bar.render()
        #expect(bar.urlBox.layer?.borderColor == theme.color(.border).cgColor)
    }

    @Test func `focusing the URL field shows the focus ring before any typing`() {
        let bar = bar()
        #expect(bar.urlBox.layer?.borderColor == theme.color(.border).cgColor)
        window.makeFirstResponder(bar.urlField)
        #expect(bar.urlBox.layer?.borderColor == theme.color(.focusRing).cgColor)
    }

    @Test func `typing in the URL field fills Params`() {
        let bar = bar()
        bar.urlField.stringValue = "https://h/?a=1&b=2"
        bar.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: bar.urlField))
        #expect(model.tab.definition.params == [Row(name: "a", value: "1"), Row(name: "b", value: "2")])
    }

    @Test func `editing Params rewrites the URL text, with ? = & dimmed`() {
        let bar = bar()
        model.tab.definition.url = "https://h/v1"
        model.tab.definition.params = [Row(name: "limit", value: "20")]
        bar.render()
        #expect(bar.urlField.stringValue == "https://h/v1?limit=20")
        let text = bar.urlField.attributedStringValue
        let mark = (text.string as NSString).range(of: "?").location
        #expect(text.attribute(.foregroundColor, at: mark, effectiveRange: nil) as? NSColor == theme.color(.textSecondary))
        #expect(text.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor == theme.color(.text))
    }

    @Test func `the method menu lists the seven methods and nothing else`() {
        let bar = bar()
        #expect(bar.methodMenu.items.filter { !$0.isSeparatorItem }.map(\.title)
            == ["GET", "POST", "PUT", "PATCH", "DELETE", "HEAD", "OPTIONS"])
    }

    @Test func `picking a method sets it and colors the label`() throws {
        let bar = bar()
        let post = try #require(bar.methodMenu.items.first { $0.title == "POST" })
        bar.pickMethod(post)
        bar.render()
        #expect(model.tab.definition.method == "POST")
        let title = bar.methodButton.attributedTitle
        #expect(title.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor == theme.color(.methodPost))
    }

    @Test func `PROPFIND fits the pop-up without truncation`() {
        model.setMethod("PROPFIND")
        let bar = bar()
        let title = bar.methodButton.attributedTitle.size().width
        #expect(bar.methodButton.frame.width >= title)
        #expect(bar.methodButton.frame.width <= 128)
    }

    @Test func `a 2,048-character URL stays on one line and fades at the trailing edge`() {
        let bar = bar()
        model.tab.definition.url = "https://h/" + String(repeating: "a", count: 2_038)
        bar.render()
        bar.layoutSubtreeIfNeeded()
        #expect(bar.urlField.usesSingleLineMode && bar.urlField.cell?.wraps == false)
        #expect(bar.urlField.frame.height < 20)
        #expect(bar.isURLFaded)
    }

    @Test func `a note shows its glyph and a close button that dismisses it`() {
        let bar = bar()
        model.message = .note("Ignored: --retry, -s")
        bar.render()
        #expect(!bar.messageLine.isHidden)
        #expect(bar.messageText.stringValue == "Ignored: --retry, -s")
        #expect(bar.messageText.textColor == theme.color(.textSecondary))
        #expect(bar.messageGlyph.image != nil && !bar.messageClose.isHidden)
        bar.messageClose.performClick(nil)
        #expect(model.message == nil)
    }

    @Test func `an error shows in the error color with no close button`() {
        let bar = bar()
        model.message = .error("No URL in this curl command.")
        bar.render()
        #expect(bar.messageText.textColor == theme.color(.error))
        #expect(bar.messageClose.isHidden)
    }

    // MARK: Curl Import

    static let chrome = """
        curl --url 'https://primo.rangga.site/provinces.json' \\
          -H 'accept: */*' \\
          -H 'if-none-match: W/"bba270476df82b3bcd972302f70835ad"' \\
          -H 'priority: u=1, i' \\
          -H 'sec-ch-ua: "Google Chrome";v="155", "Chromium";v="155", "Not(A:Brand";v="24"' \\
          -H 'sec-ch-ua-mobile: ?0' \\
          -H 'user-agent: Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko)'
        """

    @Test func `a pasted Chrome curl fills the URL, the headers and the field, and is not inserted`() {
        let bar = bar()
        #expect(bar.pasteCurl(Self.chrome))
        let definition = model.tab.definition
        #expect(definition.method == "GET" && definition.url == "https://primo.rangga.site/provinces.json")
        #expect(definition.params.isEmpty && definition.body == .none)
        #expect(definition.headers.map(\.name) == ["accept", "if-none-match", "priority", "sec-ch-ua", "sec-ch-ua-mobile", "user-agent"])
        #expect(definition.headers[1].value == #"W/"bba270476df82b3bcd972302f70835ad""#)
        #expect(definition.headers[2].value == "u=1, i")
        #expect(bar.urlField.stringValue == "https://primo.rangga.site/provinces.json")
        #expect(model.message == nil)
    }

    @Test func `a paste that is not curl is left to the field`() {
        let bar = bar()
        #expect(!bar.pasteCurl("https://h/a?b=1"))
        #expect(model.tab.definition == .empty)
    }

    @Test(arguments: [
        ("curl 'https://h", "Unterminated quote in this curl command, at character 6."), ("curl -s", "No URL in this curl command."),
    ])
    func `a curl error is a message, the Tab is unchanged and the text is not inserted`(text: String, line: String) {
        let bar = bar()
        #expect(bar.pasteCurl(text))
        #expect(model.tab.definition == .empty)
        #expect(model.message == .error(line))
    }

    @Test(arguments: [("curl https://h/a\ncurl https://h/b", "1 more command"), ("curl https://h/a\ncurl https://h/b\ncurl https://h/c", "2 more commands")])
    func `the count of extra commands agrees with its noun`(text: String, note: String) {
        let bar = bar()
        #expect(bar.pasteCurl(text))
        #expect(model.message == .note(note))
    }

    @Test func `unknown flags and extra commands go in one note`() {
        let bar = bar()
        #expect(bar.pasteCurl("curl --retry 3 -s https://h/a\ncurl https://h/b\ncurl https://h/c"))
        #expect(model.message == .note("Ignored: --retry, -s. 2 more commands"))
        #expect(model.tab.definition.url == "https://h/a")
    }

    @Test func `a data file is read as the body, and one that cannot be read leaves no body and names it`() {
        let files = DictionaryFileReading(["/tmp/a.json": Data(#"{"a":1}"#.utf8), "/tmp/bin": Data([0xFF, 0xFE])])
        let model = TabModel(transport: ScriptedTransport(.failure(.timedOut)), secrets: InMemorySecretStore(), files: files, instants: FixedInstantSource(.now))
        #expect(model.pasteInURLBar("curl -H 'Content-Type: application/json' --data-binary @/tmp/a.json https://h"))
        #expect(model.tab.definition.body == .raw(.json, #"{"a":1}"#))
        #expect(model.pasteInURLBar("curl --data-binary @/tmp/bin https://h"))
        #expect(model.tab.definition.body == .none)
        #expect(model.message == .note("/tmp/bin is not text, and binary bodies are not supported"))
    }

    nonisolated static let getWithBody = "A GET with a body won't send: macOS refuses it. Change the method or remove the body."

    @Test(arguments: [
        ("curl -X GET -d a=1 https://h", MessageLine.note(getWithBody)),
        ("curl -X get --data-raw x https://h", .note(getWithBody)),
        ("curl -s -X GET -d a=1 https://h", .note("Ignored: -s. " + getWithBody)),
        ("curl -G -d a=1 https://h", nil),
        ("curl -X DELETE -d a=1 https://h", nil),
        ("curl -d a=1 https://h", nil),
    ])
    func `a GET with a body is imported with a note that it won't send`(text: String, note: MessageLine?) {
        #expect(model.pasteInURLBar(text))
        #expect(model.message == note)
    }

    @Test func `after a pasted curl the field shows the URL with a caret at the end, not selected`() throws {
        let bar = bar()
        window.makeFirstResponder(bar.urlField)
        #expect(bar.pasteCurl(Self.chrome))
        let editor = try #require(bar.urlField.currentEditor())
        let end = ("https://primo.rangga.site/provinces.json" as NSString).length
        #expect(editor.selectedRange == NSRange(location: end, length: 0))
    }

    @Test func `Undo with the field focused puts back the Tab, the field and the note, and Redo imports again`() throws {
        let bar = bar()
        window.makeFirstResponder(bar.urlField)
        #expect(bar.pasteCurl("curl --retry 3 https://h/a -H 'x-one: 1'"))
        #expect(model.message == .note("Ignored: --retry"))
        let undo = try #require(bar.undoManager)
        undo.undo()
        #expect(model.tab.definition == .empty && model.message == nil)
        #expect(bar.urlField.stringValue == "" && (bar.urlField.currentEditor()?.string ?? "") == "")
        #expect(undo.canRedo)
        undo.redo()
        #expect(model.tab.definition.url == "https://h/a" && model.tab.definition.headers.map(\.name) == ["x-one"])
        #expect(model.message == .note("Ignored: --retry"))
        #expect(bar.urlField.stringValue == "https://h/a")
    }

    @Test func `the field editor offers a paste to the field before inserting it`() throws {
        let bar = bar()
        let editor = try #require(bar.urlField.cell?.fieldEditor(for: bar.urlField) as? PasteFieldEditor)
        editor.pasteboard = NSPasteboard(name: NSPasteboard.Name("raccoon-tests-paste"))
        editor.pasteboard.clearContents()
        editor.pasteboard.setString(Self.chrome, forType: .string)
        editor.paste(nil)
        #expect(model.tab.definition.url == "https://primo.rangga.site/provinces.json")
        #expect(editor.string == "")
    }
}

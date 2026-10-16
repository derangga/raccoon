import AppKit
@testable import Raccoon
import RaccoonDomain
import RaccoonTesting
import Testing

@MainActor
struct URLBarTests {
    let theme = ThemeEnvironment(catalog: ThemeCatalog.load(), isDark: false)
    let model = TabModel(transport: ScriptedTransport(.failure(.timedOut)), secrets: InMemorySecretStore(), instants: FixedInstantSource(.now))
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

    @Test func `the method menu lists the seven methods, then Other…`() {
        let bar = bar()
        #expect(bar.methodMenu.items.filter { !$0.isSeparatorItem }.map(\.title)
            == ["GET", "POST", "PUT", "PATCH", "DELETE", "HEAD", "OPTIONS", "Other…"])
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

    @Test func `Other… takes free text, stored uppercased`() {
        let bar = bar()
        bar.editOtherMethod()
        #expect(!bar.methodField.isHidden)
        bar.methodField.stringValue = "propfind"
        bar.controlTextDidEndEditing(Notification(name: NSControl.textDidEndEditingNotification, object: bar.methodField))
        #expect(model.tab.definition.method == "PROPFIND")
        #expect(bar.methodField.isHidden)
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
}

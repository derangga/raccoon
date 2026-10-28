import AppKit
@testable import Raccoon
import RaccoonDomain
import Testing

/// The Variable popover: which token is under the pointer, what the panel says and how it
/// is held back from taking focus.
@MainActor
struct VariableHoverTests {
    let theme = ThemeEnvironment(catalog: ThemeCatalog.load(), isDark: false)
    let name = { (raw: String) in VariableName(raw)! }

    var kinds: VariableKinds {
        VariableKinds(
            active: Environment(name: "Staging", entries: [VariableEntry(name: name("key"), value: .secret)]),
            globals: Globals(entries: [VariableEntry(name: name("host"), value: .plain("h.example.com"))])
        )
    }

    /// A text view in a window, holding `text` in SF Mono 12 on one line.
    func makeView(_ text: String) -> (NSWindow, NSTextView) {
        let view = NSTextView(frame: NSRect(x: 0, y: 0, width: 600, height: 40))
        view.textContainer?.widthTracksTextView = false
        view.string = text
        view.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        let window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 600, height: 40), styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = view
        window.orderFront(nil)
        return (window, view)
    }

    func layout(_ view: NSTextView) -> TextLayout {
        TextLayout(storage: view.textStorage!, manager: view.layoutManager!, origin: view.textContainerOrigin, space: view)
    }

    /// Where the middle of `range` is, in the view.
    func center(of range: NSRange, in view: NSTextView) -> NSPoint {
        let manager = view.layoutManager!
        let box = manager.boundingRect(forGlyphRange: manager.glyphRange(forCharacterRange: range, actualCharacterRange: nil), in: view.textContainer!)
        return NSPoint(x: view.textContainerOrigin.x + box.midX, y: view.textContainerOrigin.y + box.midY)
    }

    @Test func `the pointer is over a token only inside its characters`() {
        let (window, view) = makeView("GET {{host}}/{{ key }}")
        defer { window.orderOut(nil) }

        func hit(_ point: NSPoint) -> String? { VariableHover.hit(point, in: layout(view))?.token.name.rawValue }

        #expect(hit(center(of: NSRange(location: 4, length: 8), in: view)) == "host")
        #expect(hit(center(of: NSRange(location: 13, length: 9), in: view)) == "key")
        #expect(hit(center(of: NSRange(location: 0, length: 3), in: view)) == nil)
        #expect(hit(center(of: NSRange(location: 12, length: 1), in: view)) == nil)
        // Past the last character, and below the line.
        #expect(hit(NSPoint(x: 400, y: view.textContainerOrigin.y + 6)) == nil)
        #expect(hit(NSPoint(x: center(of: NSRange(location: 4, length: 8), in: view).x, y: 36)) == nil)
    }

    func popover(_ name: String) -> VariablePopoverView {
        VariableTooltipPanel.content(kinds.tooltip(for: self.name(name)), theme: theme)
    }

    @Test func `each kind reads as designed, and a secret never shows a value`() {
        let host = popover("host")
        #expect(host.valueText?.string == "h.example.com" && host.message == nil)
        #expect(host.chip?.stringValue == "G" && host.source?.stringValue == "Globals")
        #expect(host.link.title == "Variables in request →")

        let key = popover("key")
        #expect(key.valueText == nil && key.message?.stringValue == "Secret")
        #expect(key.chip?.stringValue == "E" && key.source?.stringValue == "Staging")

        let missing = popover("charge_id")
        #expect(missing.valueText == nil && missing.message?.stringValue == "Not defined in Staging or Globals")
        #expect(missing.message?.textColor == theme.color(.variableUndefined))
        #expect(missing.chip == nil && missing.source == nil)
        #expect(missing.link.title == "Variables in request →")
    }

    @Test func `the value is SF Mono 11 in a bordered box, selectable but never editable`() throws {
        let host = popover("host")
        let box = try #require(host.valueBox)
        let text = try #require(host.valueText)
        #expect(box.layer?.borderWidth == 1 && box.layer?.borderColor == theme.color(.border).cgColor)
        #expect(box.layer?.cornerRadius == 4)
        #expect(text.backgroundColor == theme.color(.backgroundRecessed))
        #expect(text.font?.pointSize == 11 && text.font?.isFixedPitch == true)
        #expect(text.isSelectable && !text.isEditable)
    }

    @Test func `a long value stops at five lines and scrolls; the popover is always 320 pt wide`() throws {
        let long = VariableTooltipPanel.content(.defined(name("token"), source: "Staging", value: String(repeating: "a", count: 600)), theme: theme)
        let short = VariableTooltipPanel.content(.defined(name("a"), source: "Staging", value: "b"), theme: theme)
        let box = try #require(long.valueBox)

        #expect(long.frame.width == 320 && short.frame.width == 320)
        // Five 16 pt lines, 4 pt padding above and below, a 1 pt border: 80 + 8 + 2.
        #expect(box.frame.height == 90)
        #expect(try #require(short.valueBox).frame.height == 16 + 8 + 2)
        #expect(box.hasVerticalScroller)
        #expect(try #require(box.documentView).frame.height > box.contentSize.height)
        // Nothing sticks out of the popover.
        for part in [box, long.link] as [NSView] { #expect(long.bounds.contains(part.convert(part.bounds, to: long))) }
    }

    @Test func `the link closes the popover and asks for the Variable in the inspector`() throws {
        let (window, _) = makeView("{{host}}")
        defer { window.orderOut(nil) }
        let panel = VariableTooltipPanel()
        var revealed: [VariableName] = []
        panel.onReveal = { revealed.append($0) }
        panel.show(kinds.tooltip(for: name("charge_id")), theme: theme, near: window.frame, in: window)

        try #require(panel.view).link.performClick(nil)

        #expect(revealed == [name("charge_id")])
        #expect(!panel.isShown && panel.monitor == nil)
    }

    @Test func `showing it changes neither the key window nor the first responder`() {
        let (window, view) = makeView("{{host}}")
        defer { window.orderOut(nil) }
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 50, height: 20))
        view.addSubview(field)
        window.makeFirstResponder(field)
        let responder = window.firstResponder
        let keyBefore = NSApp.keyWindow
        let panel = VariableTooltipPanel()

        panel.show(kinds.tooltip(for: name("host")), theme: theme, near: window.frame, in: window)

        #expect(panel.isShown)
        #expect(window.firstResponder === responder)
        #expect(NSApp.keyWindow === keyBefore)
        panel.hide()
    }

    @Test func `clicks and ⌘ keys inside the popover keep it; other keys and clicks outside close it`() throws {
        let (window, _) = makeView("{{host}}")
        defer { window.orderOut(nil) }
        let panel = VariableTooltipPanel()
        panel.show(kinds.tooltip(for: name("host")), theme: theme, near: window.frame, in: window)
        defer { panel.hide() }
        let inside = try #require(panel.windowNumber)

        func key(_ characters: String, _ flags: NSEvent.ModifierFlags, in number: Int) throws -> NSEvent {
            try #require(NSEvent.keyEvent(
                with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0, windowNumber: number,
                context: nil, characters: characters, charactersIgnoringModifiers: characters, isARepeat: false, keyCode: 0
            ))
        }
        func click(in number: Int) throws -> NSEvent {
            try #require(NSEvent.mouseEvent(
                with: .leftMouseDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: number,
                context: nil, eventNumber: 0, clickCount: 1, pressure: 1
            ))
        }

        #expect(!panel.closes(try click(in: inside)))
        #expect(!panel.closes(try key("c", .command, in: inside)))
        #expect(panel.closes(try key("a", [], in: inside)))
        #expect(panel.closes(try click(in: window.windowNumber)))
        #expect(panel.closes(try key("c", .command, in: window.windowNumber)))
    }

    @Test func `leaving the token waits for the pointer: over the popover it stays, until the pointer leaves it`() {
        let (window, view) = makeView("{{host}} x")
        defer { window.orderOut(nil) }
        var pointer = NSPoint(x: -9999, y: -9999)
        let panel = VariableTooltipPanel(grace: 0, pointer: { pointer })
        let hover = VariableHover(panel: panel, delay: 0, layout: { layout(view) }, kinds: { kinds }, theme: { theme })
        let token = view.convert(center(of: NSRange(location: 0, length: 8), in: view), to: nil)

        hover.pointerMoved(to: token)
        pointer = NSPoint(x: panel.frame!.midX, y: panel.frame!.midY)
        hover.exited()
        #expect(panel.isShown)

        panel.pointerLeft()
        #expect(!panel.isShown)

        hover.pointerMoved(to: token)
        pointer = NSPoint(x: -9999, y: -9999)
        hover.exited()
        #expect(!panel.isShown && panel.monitor == nil)
    }

    @Test func `it goes on any key, and the key monitor goes with it`() throws {
        let (window, _) = makeView("{{host}}")
        defer { window.orderOut(nil) }
        let panel = VariableTooltipPanel()
        panel.show(kinds.tooltip(for: name("host")), theme: theme, near: window.frame, in: window)
        #expect(panel.isShown && panel.monitor != nil)

        let key = try #require(NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber,
            context: nil, characters: "a", charactersIgnoringModifiers: "a", isARepeat: false, keyCode: 0
        ))
        NSApp.sendEvent(key)

        #expect(!panel.isShown)
        #expect(panel.monitor == nil)
    }

    @Test func `the pointer opens it over a token, moves it to the next at once, and closes it off a token`() {
        let (window, view) = makeView("{{host}} x {{key}}")
        defer { window.orderOut(nil) }
        let panel = VariableTooltipPanel(grace: 0, pointer: { NSPoint(x: -9999, y: -9999) })
        let hover = VariableHover(panel: panel, delay: 0, layout: { layout(view) }, kinds: { kinds }, theme: { theme })
        func move(to range: NSRange) { hover.pointerMoved(to: view.convert(center(of: range, in: view), to: nil)) }

        move(to: NSRange(location: 0, length: 8))
        #expect(panel.isShown)
        let first = panel.frame
        move(to: NSRange(location: 11, length: 7))
        #expect(panel.isShown && panel.frame != first)
        move(to: NSRange(location: 8, length: 3))
        #expect(!panel.isShown)

        move(to: NSRange(location: 0, length: 8))
        hover.exited()
        #expect(!panel.isShown && panel.monitor == nil)
    }

    @Test func `it waits out the delay before the first tooltip`() {
        let (window, view) = makeView("{{host}}")
        defer { window.orderOut(nil) }
        let panel = VariableTooltipPanel()
        let hover = VariableHover(panel: panel, delay: 60, layout: { layout(view) }, kinds: { kinds }, theme: { theme })

        hover.pointerMoved(to: view.convert(center(of: NSRange(location: 0, length: 8), in: view), to: nil))

        #expect(!panel.isShown)
        hover.exited()
    }

    @Test func `a field at rest is laid out where its cell draws it, so its tokens can be hit`() {
        let field = VariableField(frame: NSRect(x: 0, y: 0, width: 300, height: 24))
        field.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        field.stringValue = "a/{{host}}"
        let layout = TextLayout.atRest(field, space: NSView(frame: field.bounds))

        let onToken = NSPoint(x: layout.origin.x + 2 + 5 * 7.2, y: layout.origin.y + 6)
        let onText = NSPoint(x: layout.origin.x + 2 + 1 * 7.2, y: layout.origin.y + 6)

        #expect(VariableHover.hit(onToken, in: layout)?.token.name.rawValue == "host")
        #expect(VariableHover.hit(onText, in: layout) == nil)
    }
}

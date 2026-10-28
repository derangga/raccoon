import AppKit
@testable import Raccoon
import RaccoonDomain
import RaccoonTesting
import Testing

/// One editor for every Tab: switching rebinds it and brings back where each Tab was.
@MainActor
struct TabSwitchTests {
    let theme = ThemeEnvironment(catalog: ThemeCatalog.load(), isDark: false)
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 700), styleMask: [], backing: .buffered, defer: false)

    func tab(url: String, body: String) -> TabModel {
        let model = TabModel(transport: ScriptedTransport(.failure(.timedOut)), secrets: InMemorySecretStore(), files: DictionaryFileReading([:]),
                             instants: FixedInstantSource(.now), clipboard: RecordingClipboardWriter())
        model.tab.definition.url = url
        model.tab.definition.body = .raw(.text, body)
        return model
    }

    func shown(_ model: TabModel) -> TabViewController {
        let controller = TabViewController(model: model, theme: theme)
        window.contentView = controller.view
        controller.view.layoutSubtreeIfNeeded()
        return controller
    }

    let long = (1...400).map { "line \($0)" }.joined(separator: "\n")

    @Test func `switching rebinds the same views to the other Tab`() async {
        let (a, b) = (tab(url: "https://a.example", body: "a"), tab(url: "https://b.example", body: "b"))
        let controller = shown(a)
        let views = [controller.urlBar, controller.editor, controller.viewer] as [NSView]

        controller.bind(b)
        #expect([controller.urlBar, controller.editor, controller.viewer] as [NSView] == views)
        #expect(controller.urlBar.urlField.stringValue == "https://b.example")
        #expect(controller.editor.bodyPane.textView.string == "b")

        b.typeInURLBar("https://b.example/2")
        await Task.yield()
        #expect(controller.urlBar.urlField.stringValue == "https://b.example/2")
        #expect(a.tab.definition.url == "https://a.example")
    }

    @Test func `the body's scroll position and selection and the section come back`() throws {
        let (a, b) = (tab(url: "https://a.example", body: long), tab(url: "https://b.example", body: "b"))
        let controller = shown(a)
        let body = controller.editor.bodyPane.textView
        controller.editor.select(.body)
        controller.view.layoutSubtreeIfNeeded()
        body.layoutManager?.ensureLayout(for: body.textContainer!)
        body.sizeToFit()
        body.setSelectedRange(NSRange(location: 2_000, length: 7))
        body.scroll(NSPoint(x: 0, y: 1_500))
        let origin = try #require(body.enclosingScrollView).contentView.bounds.origin
        #expect(origin.y > 1_000)

        controller.bind(b)
        controller.editor.select(.headers)
        #expect(body.selectedRange() != NSRange(location: 2_000, length: 7))

        controller.bind(a)
        controller.view.layoutSubtreeIfNeeded()
        #expect(controller.editor.selected == .body)
        #expect(body.selectedRange() == NSRange(location: 2_000, length: 7))
        #expect(body.enclosingScrollView?.contentView.bounds.origin == origin)

        controller.bind(b)
        #expect(controller.editor.selected == .headers)
    }

    @Test func `undo does not reach across Tabs`() {
        let (a, b) = (tab(url: "", body: ""), tab(url: "", body: ""))
        let controller = shown(a)
        _ = controller.urlBar.pasteCurl("curl https://a.example")
        #expect(window.undoManager?.canUndo == true)
        controller.bind(b)
        #expect(window.undoManager?.canUndo == false)
    }

    @Test func `a field being edited in the Tab ends its edit when another Tab is bound`() {
        let (a, b) = (tab(url: "https://a.example", body: "a"), tab(url: "https://b.example", body: "b"))
        let controller = shown(a)
        let field = controller.urlBar.urlField
        window.makeFirstResponder(field)
        #expect(field.currentEditor() != nil)

        controller.bind(b)

        #expect(field.currentEditor() == nil)
        #expect(window.firstResponder === window)
    }

    @Test func `focus outside the Tab, in the sidebar's outline, stays there when another Tab is bound`() {
        let (a, b) = (tab(url: "https://a.example", body: "a"), tab(url: "https://b.example", body: "b"))
        let controller = TabViewController(model: a, theme: theme)
        let host = NSView(frame: NSRect(x: 0, y: 0, width: 900, height: 700))
        let outline = NSOutlineView(frame: NSRect(x: 0, y: 0, width: 100, height: 100))
        controller.view.frame = NSRect(x: 100, y: 0, width: 800, height: 700)
        outline.addTableColumn(NSTableColumn(identifier: NSUserInterfaceItemIdentifier("name")))
        host.addSubview(outline)
        host.addSubview(controller.view)
        window.contentView = host
        window.makeFirstResponder(outline)
        #expect(window.firstResponder === outline)

        controller.bind(b)

        #expect(window.firstResponder === outline)
    }
}

import AppKit
@testable import Raccoon
import RaccoonDomain
import RaccoonTesting
import Testing

@MainActor
struct CopyAsCurlTests {
    let theme = ThemeEnvironment(catalog: ThemeCatalog.load(), isDark: false)
    let clipboard = RecordingClipboardWriter()
    let model: TabModel

    init() {
        model = TabModel(transport: ScriptedTransport(.failure(.timedOut)), secrets: InMemorySecretStore(), files: DictionaryFileReading([:]),
                         instants: FixedInstantSource(.now), clipboard: clipboard)
    }

    func copyItem() throws -> NSMenuItem {
        try #require(MainMenu.make().item(withTitle: "Edit")?.submenu?.item(withTitle: "Copy as Curl"))
    }

    @Test func `Copy as Curl puts the Tab's request on the clipboard as curl`() {
        model.tab.definition.method = "POST"
        model.tab.definition.url = "https://h/a"
        model.tab.definition.headers = [Row(name: "x-one", value: "1"), Row(name: "x-off", value: "2", isEnabled: false)]
        model.tab.definition.body = .raw(.json, #"{"a":1}"#)
        model.copyAsCurl()
        #expect(clipboard.string == "curl -X POST 'https://h/a' \\\n  -H 'x-one: 1' \\\n  --data-raw '{\"a\":1}'")
    }

    @Test func `Edit has Copy as Curl on ⇧⌘C, disabled on the Tab until its URL resolves`() throws {
        let item = try copyItem()
        #expect(item.keyEquivalent == "c" && item.keyEquivalentModifierMask == [.command, .shift])
        let controller = TabViewController(model: model, theme: theme)
        #expect(!controller.validateMenuItem(item))
        model.typeInURLBar("https://h/a?b=1")
        #expect(controller.validateMenuItem(item))
        controller.copyAsCurl(item)
        #expect(clipboard.string == "curl 'https://h/a?b=1'")
    }

    @Test func `the URL bar's menu and the URL field's menu offer Copy as Curl`() throws {
        let bar = URLBar(model: model, theme: theme)
        #expect(bar.menu?.item(withTitle: "Copy as Curl")?.action == #selector(TabViewController.copyAsCurl(_:)))
        let editor = try #require(bar.urlField.cell?.fieldEditor(for: bar.urlField))
        let event = try #require(NSEvent.mouseEvent(with: .rightMouseDown, location: .zero, modifierFlags: [], timestamp: 0,
                                                     windowNumber: 0, context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
        #expect(editor.menu(for: event)?.item(withTitle: "Copy as Curl") != nil)
    }
}

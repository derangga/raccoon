import AppKit
@testable import Raccoon
import RaccoonData
import RaccoonDomain
import RaccoonTesting
import Testing

@MainActor
struct CloseTabTests {
    let temp = FileManager.default.temporaryDirectory.appending(path: "raccoon-\(UUID())")

    func makeWindow(transport: ScriptedTransport = ScriptedTransport(.failure(.timedOut))) -> WindowModel {
        WindowModel(
            dataFolder: .test(temp.appending(path: "Raccoon")), folderWatch: ManualFolderWatch(),
            sessionStore: DiskSessionStore(directory: temp.appending(path: "Support")), secrets: InMemorySecretStore(),
            instants: FixedInstantSource(.now),
            makeTab: {
                TabModel(transport: transport, secrets: InMemorySecretStore(), files: DictionaryFileReading([:]),
                         instants: FixedInstantSource(.now), clipboard: RecordingClipboardWriter())
            }
        )
    }

    func ids(_ window: WindowModel) -> [TabID] { window.tabs.map(\.tab.id) }

    @Test func `closing a sending Tab cancels its send, and nothing lands later`() async throws {
        let response = Response(status: 200, headers: [], body: Data("late".utf8), elapsed: .milliseconds(1), byteCount: 4)
        let window = makeWindow(transport: ScriptedTransport(.success(response)))
        window.newTab()
        let sending = window.tabs[1]
        sending.typeInURLBar("http://localhost/slow")
        sending.send()
        let task = try #require(sending.inFlight)

        window.close(sending.tab.id)
        await task.value

        #expect(sending.tab.response == .idle)
        #expect(sending.presented == nil)
        #expect(!ids(window).contains(sending.tab.id))
    }

    @Test func `closing the selected Tab selects the one after it, or before it when it was last`() {
        let window = makeWindow()
        window.newTab()
        window.newTab()
        let (a, b, c) = (window.tabs[0].tab.id, window.tabs[1].tab.id, window.tabs[2].tab.id)

        window.select(b)
        window.close(b)
        #expect(ids(window) == [a, c])
        #expect(window.selected == c)

        window.close(c)
        #expect(window.selected == a)
    }

    @Test func `closing a Tab that is not selected keeps the selection`() {
        let window = makeWindow()
        window.newTab()
        let (a, b) = (window.tabs[0].tab.id, window.tabs[1].tab.id)
        window.close(a)
        #expect(ids(window) == [b])
        #expect(window.selected == b)
    }

    @Test func `closing the last Tab opens an empty Draft`() {
        let window = makeWindow()
        let only = window.tabs[0].tab.id
        window.tabs[0].typeInURLBar("https://api.example.com")
        window.close(only)
        #expect(window.tabs.count == 1)
        #expect(window.tabs[0].tab.id != only)
        #expect(window.tabs[0].tab.source == .draft && window.tabs[0].tab.definition == .empty)
        #expect(window.selected == window.tabs[0].tab.id)
    }

    /// Records each question and answers it with `answer`.
    @MainActor final class ScriptedAsk {
        var answer: CloseChoice
        var asked: [TabID] = []
        init(_ answer: CloseChoice) { self.answer = answer }
        func ask(_ model: TabModel, _ reply: @escaping (CloseChoice) -> Void) {
            asked.append(model.tab.id)
            reply(answer)
        }
    }

    @Test func `an empty Draft closes without asking, a non-empty Draft and a Dirty Tab ask`() {
        let window = makeWindow()
        let ask = ScriptedAsk(.cancel)
        let closer = TabCloser(window: window, saver: DraftSaver(window: window, ask: { _, _, reply in reply(nil) }, focusURL: {}), ask: ask.ask)
        for _ in 0..<2 { window.newTab() }
        let (empty, draft, dirty) = (window.tabs[0], window.tabs[1], window.tabs[2])
        draft.typeInURLBar("https://api.example.com/v1/webhooks")
        dirty.tab.source = .request(RequestID(UUID()))
        dirty.tab.baseline = dirty.tab.definition
        dirty.tab.definition.method = "POST"

        closer.close(empty)
        closer.close(draft)
        closer.close(dirty)

        #expect(ask.asked == [draft.tab.id, dirty.tab.id])
        #expect(ids(window) == [draft.tab.id, dirty.tab.id])
    }

    @Test func `Don't Save closes the Tab, Cancel keeps it`() {
        let window = makeWindow()
        window.tabs[0].typeInURLBar("https://api.example.com")
        window.newTab()
        window.tabs[1].typeInURLBar("https://api.example.com/2")
        let ask = ScriptedAsk(.cancel)
        let closer = TabCloser(window: window, saver: DraftSaver(window: window, ask: { _, _, reply in reply(nil) }, focusURL: {}), ask: ask.ask)
        let kept = window.tabs[1]

        closer.close(kept)
        #expect(ids(window).contains(kept.tab.id))
        #expect(window.selected == kept.tab.id)

        ask.answer = .dontSave
        closer.close(kept)
        #expect(!ids(window).contains(kept.tab.id))
    }
}

/// The live prompt: a sheet on the window.
@MainActor
struct CloseConfirmTests {
    func draft() -> TabModel {
        let model = TabModel(transport: ScriptedTransport(.failure(.timedOut)), secrets: InMemorySecretStore(), files: DictionaryFileReading([:]),
                             instants: FixedInstantSource(.now), clipboard: RecordingClipboardWriter())
        model.typeInURLBar("https://api.example.com/v1/webhooks")
        return model
    }

    @Test func `a Draft's alert names it, offers Save on Return, a red Don't Save and Cancel`() {
        let alert = CloseConfirm.alert(for: draft(), name: "/v1/webhooks")
        #expect(alert.messageText == "Save “/v1/webhooks” before closing?")
        #expect(alert.informativeText == "This Draft hasn't been saved. Its request will be lost.")
        #expect(alert.buttons.map(\.title) == ["Save", "Don't Save", "Cancel"])
        #expect(alert.buttons.map(\.hasDestructiveAction) == [false, true, false])
        // Return saves: no key a hand rests on discards work.
        #expect(alert.buttons[0].keyEquivalent == "\r")
        #expect(alert.buttons[1].keyEquivalent == "d" && alert.buttons[1].keyEquivalentModifierMask == .command)
        #expect(alert.buttons[2].keyEquivalent == "\u{1b}")
    }

    @Test func `a Dirty Tab's alert speaks of the Request's edits`() {
        let model = draft()
        model.tab.source = .request(RequestID(UUID()))
        model.tab.baseline = .empty
        #expect(CloseConfirm.alert(for: model, name: "Create charge").informativeText == "Your edits to this Request haven't been saved and will be lost.")
    }

    @Test func `it is a sheet on the window, and Cancel gives focus back to where it was`() async throws {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 400), styleMask: [.titled], backing: .buffered, defer: false)
        let field = NSTextField(string: "")
        window.contentView?.addSubview(field)
        window.makeKeyAndOrderFront(nil)
        defer { window.orderOut(nil) }
        window.makeFirstResponder(field)
        let focused = window.firstResponder

        var choice: CloseChoice?
        CloseConfirm.ask(draft(), name: "/v1/webhooks", in: window) { choice = $0 }
        let sheet = try #require(window.attachedSheet)
        window.endSheet(sheet, returnCode: .alertThirdButtonReturn)
        for _ in 0..<5 { await Task.yield() }

        #expect(choice == .cancel)
        #expect(window.firstResponder === focused)
    }
}

@MainActor
struct CloseTabMenuTests {
    @Test func `File has Close Tab on ⌘W, for the AppDelegate`() throws {
        let controller = ThemeController(defaults: UserDefaults(suiteName: "raccoon-\(UUID())")!, catalog: ThemeCatalog.load(), appearanceSource: NSView())
        let file = try #require(MainMenu.make(theme: controller).item(withTitle: "File")?.submenu)
        let close = try #require(file.item(withTitle: "Close Tab"))
        #expect(close.keyEquivalent == "w" && close.keyEquivalentModifierMask == .command)
        #expect(close.action == #selector(AppDelegate.closeTab(_:)))
    }
}

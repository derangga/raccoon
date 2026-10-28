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
            sessionStore: DiskSessionStore(directory: temp.appending(path: "Support"), root: temp.appending(path: "Raccoon").path), secrets: InMemorySecretStore(),
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

    @Test func `closing the last Tab leaves no Tab and no selection, and the Session says so`() {
        let window = makeWindow()
        window.close(window.tabs[0].tab.id)
        #expect(window.tabs.isEmpty)
        #expect(window.selected == nil && window.selectedTab == nil)
        #expect(window.session == Session(tabs: [], selected: nil, activeEnvironment: nil))
    }

    @Test func `with no Tab open, ⌘T opens a Draft and selects it`() {
        let window = makeWindow()
        window.close(window.tabs[0].tab.id)
        window.newTab()
        #expect(window.tabs.count == 1)
        #expect(window.selected == window.tabs[0].tab.id)
        #expect(window.tabs[0].tab.source == .draft && window.tabs[0].tab.definition == .empty)
    }

    @Test func `with no Tab open, Tab switching does nothing`() {
        let window = makeWindow()
        window.close(window.tabs[0].tab.id)
        window.selectNext()
        window.selectPrevious()
        window.select(number: 1)
        #expect(window.selected == nil)
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
        let closer = TabCloser(window: window, saver: DraftSaver(window: window, ask: { _, _, reply in reply(nil) }, focusURL: {}), memory: CloseMemory(), ask: ask.ask)
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
        let closer = TabCloser(window: window, saver: DraftSaver(window: window, ask: { _, _, reply in reply(nil) }, focusURL: {}), memory: CloseMemory(), ask: ask.ask)
        let kept = window.tabs[1]

        closer.close(kept)
        #expect(ids(window).contains(kept.tab.id))
        #expect(window.selected == kept.tab.id)

        ask.answer = .dontSave(alwaysDiscard: false)
        closer.close(kept)
        #expect(!ids(window).contains(kept.tab.id))
    }

    /// The preference in memory, as UserDefaults would hold it.
    @MainActor final class Remembered {
        var alwaysDiscards = false
        var memory: CloseMemory { CloseMemory(alwaysDiscards: { self.alwaysDiscards }, remember: { self.alwaysDiscards = $0 }) }
    }

    func losableTab(_ window: WindowModel) -> TabModel {
        window.newTab()
        let tab = window.tabs[1]
        tab.typeInURLBar("https://api.example.com/v1/webhooks")
        return tab
    }

    @Test(arguments: [
        (CloseChoice.dontSave(alwaysDiscard: true), true),
        (.dontSave(alwaysDiscard: false), false),
        (.cancel, false),
    ])
    func `only Don't Save with the box ticked remembers to always discard`(choice: CloseChoice, remembered: Bool) {
        let window = makeWindow()
        let tab = losableTab(window)
        let preference = Remembered()
        let closer = TabCloser(window: window, saver: DraftSaver(window: window, ask: { _, _, reply in reply(nil) }, focusURL: {}),
                               memory: preference.memory, ask: ScriptedAsk(choice).ask)

        closer.close(tab)

        #expect(preference.alwaysDiscards == remembered)
    }

    @Test func `while always discarding, a losable Tab closes without asking`() {
        let window = makeWindow()
        let tab = losableTab(window)
        let preference = Remembered()
        preference.alwaysDiscards = true
        let ask = ScriptedAsk(.cancel)
        let closer = TabCloser(window: window, saver: DraftSaver(window: window, ask: { _, _, reply in reply(nil) }, focusURL: {}),
                               memory: preference.memory, ask: ask.ask)

        closer.close(tab)

        #expect(ask.asked.isEmpty)
        #expect(!ids(window).contains(tab.tab.id))
    }

    @Test func `turning the preference off brings the sheet back on the next close`() {
        let window = makeWindow()
        let tab = losableTab(window)
        let preference = Remembered()
        preference.alwaysDiscards = true
        let ask = ScriptedAsk(.cancel)
        let closer = TabCloser(window: window, saver: DraftSaver(window: window, ask: { _, _, reply in reply(nil) }, focusURL: {}),
                               memory: preference.memory, ask: ask.ask)

        preference.memory.remember(false)
        closer.close(tab)

        #expect(ask.asked == [tab.tab.id])
    }
}

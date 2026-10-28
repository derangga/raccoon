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
        let closer = TabCloser(window: window, saver: DraftSaver(window: window, ask: { _, _, reply in reply(nil) }, focusURL: {}), memory: CloseMemory(), confirmForce: { _, reply in reply(true) }, ask: ask.ask)
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
        let closer = TabCloser(window: window, saver: DraftSaver(window: window, ask: { _, _, reply in reply(nil) }, focusURL: {}), memory: CloseMemory(), confirmForce: { _, reply in reply(true) }, ask: ask.ask)
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
                               memory: preference.memory, confirmForce: { _, reply in reply(true) }, ask: ScriptedAsk(choice).ask)

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
                               memory: preference.memory, confirmForce: { _, reply in reply(true) }, ask: ask.ask)

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
                               memory: preference.memory, confirmForce: { _, reply in reply(true) }, ask: ask.ask)

        preference.memory.remember(false)
        closer.close(tab)

        #expect(ask.asked == [tab.tab.id])
    }

    // MARK: Close from a Tab's context menu

    /// Three Tabs: an empty Draft, a non-empty Draft and a Dirty Request Tab.
    func threeTabs(_ window: WindowModel) -> (empty: TabModel, draft: TabModel, dirty: TabModel) {
        for _ in 0..<2 { window.newTab() }
        let (empty, draft, dirty) = (window.tabs[0], window.tabs[1], window.tabs[2])
        draft.typeInURLBar("https://api.example.com/v1/webhooks")
        dirty.tab.source = .request(RequestID(UUID()))
        dirty.tab.baseline = dirty.tab.definition
        dirty.tab.definition.method = "POST"
        return (empty, draft, dirty)
    }

    /// Records how many Tabs each Force Close question counted, and answers with `answer`.
    @MainActor final class ScriptedForce {
        var answer: Bool
        var counted: [Int] = []
        init(_ answer: Bool) { self.answer = answer }
        func confirm(_ losing: Int, _ reply: @escaping (Bool) -> Void) {
            counted.append(losing)
            reply(answer)
        }
    }

    func closer(_ window: WindowModel, ask: ScriptedAsk, memory: CloseMemory = CloseMemory(), force: ScriptedForce = ScriptedForce(true)) -> TabCloser {
        TabCloser(window: window, saver: DraftSaver(window: window, ask: { _, _, reply in reply(nil) }, focusURL: {}), memory: memory, confirmForce: force.confirm, ask: ask.ask)
    }

    @Test func `Close Other Tabs asks for each losable Tab in strip order and keeps the one clicked`() {
        let window = makeWindow()
        let (empty, draft, dirty) = threeTabs(window)
        let ask = ScriptedAsk(.dontSave(alwaysDiscard: false))

        closer(window, ask: ask).close(.others, of: empty)

        #expect(ask.asked == [draft.tab.id, dirty.tab.id])
        #expect(ids(window) == [empty.tab.id])
    }

    @Test func `Close All Tabs closes every Tab, asking only for the losable ones`() {
        let window = makeWindow()
        let (empty, draft, dirty) = threeTabs(window)
        let ask = ScriptedAsk(.dontSave(alwaysDiscard: false))

        closer(window, ask: ask).close(.all, of: empty)

        #expect(ask.asked == [draft.tab.id, dirty.tab.id])
        #expect(window.tabs.isEmpty && window.selected == nil)
    }

    @Test func `Cancel on one Tab stops the batch: that Tab and the ones after it stay`() {
        let window = makeWindow()
        let (empty, draft, dirty) = threeTabs(window)
        let ask = ScriptedAsk(.cancel)

        closer(window, ask: ask).close(.all, of: empty)

        // The empty Draft before the first question is already gone; nothing after Cancel is touched.
        #expect(ask.asked == [draft.tab.id])
        #expect(ids(window) == [draft.tab.id, dirty.tab.id])
    }

    @Test func `a Save that does not land stops the batch`() {
        let window = makeWindow()
        let (empty, draft, dirty) = threeTabs(window)
        let ask = ScriptedAsk(.save)

        // The Save Request sheet answers nil: cancelled, so the Draft is not saved.
        closer(window, ask: ask).close(.all, of: empty)

        #expect(ask.asked == [draft.tab.id])
        #expect(ids(window) == [draft.tab.id, dirty.tab.id])
    }

    @Test func `Force Close All Tabs counts the Tabs with something to lose, then discards them all with no Close sheet`() {
        let window = makeWindow()
        let (empty, _, _) = threeTabs(window)
        let ask = ScriptedAsk(.cancel)
        let force = ScriptedForce(true)

        closer(window, ask: ask, force: force).close(.all, of: empty, force: true)

        #expect(force.counted == [2])
        #expect(ask.asked.isEmpty)
        #expect(window.tabs.isEmpty)
    }

    @Test func `Cancel in the Force Close question closes nothing`() {
        let window = makeWindow()
        let (empty, draft, dirty) = threeTabs(window)

        closer(window, ask: ScriptedAsk(.cancel), force: ScriptedForce(false)).close(.all, of: empty, force: true)

        #expect(ids(window) == [empty.tab.id, draft.tab.id, dirty.tab.id])
    }

    @Test func `Force Close All Tabs with nothing to lose closes without a question`() {
        let window = makeWindow()
        window.newTab()
        let force = ScriptedForce(false)

        closer(window, ask: ScriptedAsk(.cancel), force: force).close(.all, of: window.tabs[0], force: true)

        #expect(force.counted.isEmpty)
        #expect(window.tabs.isEmpty)
    }

    @Test func `while always discarding, Force Close All Tabs closes without a question`() {
        let window = makeWindow()
        let (empty, _, _) = threeTabs(window)
        let preference = Remembered()
        preference.alwaysDiscards = true
        let force = ScriptedForce(false)

        closer(window, ask: ScriptedAsk(.cancel), memory: preference.memory, force: force).close(.all, of: empty, force: true)

        #expect(force.counted.isEmpty)
        #expect(window.tabs.isEmpty)
    }

    @Test(arguments: [
        (1, "1 Tab has unsaved changes. Your changes will be lost if you force close it. Are you sure you want to force close?"),
        (2, "2 Tabs have unsaved changes. Your changes will be lost if you force close these Tabs. Are you sure you want to force close?"),
        (12, "12 Tabs have unsaved changes. Your changes will be lost if you force close these Tabs. Are you sure you want to force close?"),
    ])
    func `the Force Close question counts the Tabs, in the singular for one`(count: Int, text: String) {
        #expect(ForceCloseConfirm.message(count: count) == text)
    }

    @Test func `the Force Close sheet has Cancel and Force Close only`() {
        let sheet = ForceCloseConfirm(losing: 2) { _ in }
        #expect(sheet.titleLabel.stringValue == "Confirm force close")
        #expect(buttons(in: sheet.view).map(\.title).sorted() == ["Cancel", "Force Close"])
    }

    @Test func `Force Close Tab discards the Tab it was chosen on and keeps the others`() {
        let window = makeWindow()
        let (empty, draft, dirty) = threeTabs(window)
        let ask = ScriptedAsk(.cancel)
        let force = ScriptedForce(false)

        closer(window, ask: ask, force: force).close(.tab, of: dirty, force: true)

        #expect(ask.asked.isEmpty && force.counted.isEmpty)
        #expect(ids(window) == [empty.tab.id, draft.tab.id])
    }

    @Test func `Close Other Tabs on the only Tab closes nothing`() {
        let window = makeWindow()
        let only = window.tabs[0]
        let ask = ScriptedAsk(.cancel)

        closer(window, ask: ask).close(.others, of: only)

        #expect(ids(window) == [only.tab.id])
    }

    // MARK: Duplicate Tab

    @Test func `Duplicate Tab opens a Draft with the same definition right after it, and selects it`() {
        let window = makeWindow()
        let (empty, draft, dirty) = threeTabs(window)
        window.select(empty.tab.id)

        window.duplicate(draft.tab.id)

        #expect(window.tabs.count == 4)
        let copy = window.tabs[2]
        #expect(ids(window).filter { $0 != copy.tab.id } == [empty.tab.id, draft.tab.id, dirty.tab.id])
        #expect(copy.tab.source == .draft && copy.tab.baseline == nil)
        #expect(copy.tab.definition == draft.tab.definition)
        #expect(window.selected == copy.tab.id)
    }

    @Test func `Duplicate Tab of a Request Tab is a Draft, so one Request still has one Tab`() {
        let window = makeWindow()
        let (_, _, dirty) = threeTabs(window)

        window.duplicate(dirty.tab.id)

        let copy = window.tabs[3]
        #expect(copy.tab.source == .draft)
        #expect(copy.tab.definition == dirty.tab.definition)
        #expect(dirty.tab.source != .draft)
    }

    @Test func `Duplicate Tab of a Tab that is gone does nothing`() {
        let window = makeWindow()
        window.duplicate(TabID(UUID()))
        #expect(window.tabs.count == 1)
    }

    // MARK: The close sheet

    func buttons(in view: NSView) -> [NSButton] {
        view.subviews.flatMap { ($0 as? NSButton).map { [$0] } ?? [] + buttons(in: $0) }
    }

    @Test func `the close sheet has Don't Save, Cancel and Save and a checkbox, and no ✕`() {
        let sheet = CloseConfirm(name: "Get Product Detail", isDraft: false) { _ in }
        let titles = buttons(in: sheet.view).map { $0.title.isEmpty ? "(image)" : $0.title }
        #expect(titles.sorted() == ["Always discard unsaved changes when closing a Tab", "Cancel", "Don't Save", "Save"])
    }
}

import Foundation
@testable import Raccoon
import RaccoonData
import RaccoonDomain
import RaccoonTesting
import Testing

@MainActor
struct WindowModelTests {
    let temp = FileManager.default.temporaryDirectory.appending(path: "raccoon-\(UUID())")

    func makeWindow() -> WindowModel {
        WindowModel(
            dataFolder: DiskDataFolderStore(root: temp.appending(path: "Raccoon")), folderWatch: ManualFolderWatch(),
            sessionStore: DiskSessionStore(directory: temp.appending(path: "Support")), secrets: InMemorySecretStore(),
            instants: FixedInstantSource(.now),
            makeTab: {
                TabModel(transport: ScriptedTransport(.failure(.timedOut)), secrets: InMemorySecretStore(), files: DictionaryFileReading([:]),
                         instants: FixedInstantSource(.now), clipboard: RecordingClipboardWriter())
            }
        )
    }

    func ids(_ window: WindowModel) -> [TabID] { window.tabs.map(\.tab.id) }

    @Test func `the first Tab is selected`() {
        let window = makeWindow()
        #expect(window.selected == window.tabs[0].tab.id)
        #expect(window.selectedTab === window.tabs[0])
    }

    @Test func `a new Tab is an empty Draft inserted after the selected Tab, and selected`() {
        let window = makeWindow()
        let first = window.tabs[0].tab.id
        window.newTab()
        let last = window.tabs[1].tab.id
        window.select(first)
        window.newTab()

        #expect(ids(window) == [first, window.tabs[1].tab.id, last])
        #expect(window.selected == window.tabs[1].tab.id)
        #expect(window.tabs[1].tab.source == .draft && window.tabs[1].tab.definition == .empty)
    }

    @Test func `⌘1 to ⌘8 pick by position, ⌘9 the last Tab, and a missing one changes nothing`() {
        let window = makeWindow()
        for _ in 0..<9 { window.newTab() }
        let tabs = ids(window)
        window.select(number: 2)
        #expect(window.selected == tabs[1])
        window.select(number: 9)
        #expect(window.selected == tabs[9])

        let small = makeWindow()
        small.select(number: 4)
        #expect(small.selected == small.tabs[0].tab.id)
    }

    @Test func `next and previous wrap around`() {
        let window = makeWindow()
        window.newTab()
        window.newTab()
        let tabs = ids(window)
        window.selectNext()
        #expect(window.selected == tabs[0])
        window.selectPrevious()
        #expect(window.selected == tabs[2])
        window.selectPrevious()
        #expect(window.selected == tabs[1])
    }

    @Test func `selecting an unknown Tab changes nothing`() {
        let window = makeWindow()
        window.select(TabID(UUID()))
        #expect(window.selected == window.tabs[0].tab.id)
    }
}

import AppKit
@testable import Raccoon
import RaccoonDomain
import Testing

/// A click on an Example row shows it in its Request Tab (examples.md §Show an Example), over a live store in a temp dir.
@MainActor
struct ShowExampleWindowTests {
    let base = OpenExampleTests()
    var request: RequestID { base.request }

    func requestTab(_ window: WindowModel) throws -> TabModel {
        try #require(window.tabs.first { $0.tab.source == .request(request) })
    }

    @Test func `it opens the Request's Tab after the selected one, selects it and shows the Example, with no Tab for the Example`() throws {
        let window = try base.makeWindow()

        window.showExample(request, base.example(2).id)

        #expect(window.tabs.count == 2)
        let tab = try requestTab(window)
        #expect(window.selected == tab.tab.id)
        #expect(tab.shownExample == base.example(2))
        #expect(tab.displayed == .received(base.example(2).asResponse))
        #expect(window.tabs.allSatisfy { $0.tab.example == nil })
    }

    @Test func `an open Request Tab is selected and keeps its edits, which are not Dirty-ed by it`() throws {
        let window = try base.makeWindow()
        window.openRequest(request)
        let tab = try requestTab(window)
        tab.tab.definition.url = "https://example.test/mine"
        window.select(window.tabs[0].tab.id)

        window.showExample(request, base.example(1).id)

        #expect(window.tabs.count == 2)
        #expect(window.selected == tab.tab.id)
        #expect(tab.tab.definition.url == "https://example.test/mine")
        #expect(tab.shownExample == base.example(1))
    }

    @Test func `a second Example swaps into the same Tab`() throws {
        let window = try base.makeWindow()
        window.showExample(request, base.example(1).id)

        window.showExample(request, base.example(2).id)

        #expect(window.tabs.count == 2)
        #expect(try requestTab(window).shownExample == base.example(2))
    }

    @Test func `an Example that is gone from the file shows nothing and opens nothing`() throws {
        let window = try base.makeWindow()
        try base.put([base.example(2)])

        window.showExample(request, base.example(1).id)

        #expect(window.tabs.count == 1)
        #expect(window.tabs.allSatisfy { $0.shownExample == nil })
    }

    @Test func `renaming the shown Example shows the new name, and deleting it empties the viewer`() throws {
        let window = try base.makeWindow()
        window.showExample(request, base.example(1).id)
        let tab = try requestTab(window)

        try window.updateExample(request, base.example(1).id) { $0.name = "renamed" }
        #expect(tab.shownExample?.name == "renamed")

        try window.removeExample(request, base.example(1).id)
        #expect(tab.shownExample == nil)
        #expect(tab.displayed == .idle)
    }

    @Test func `renaming another Example leaves the shown one alone`() throws {
        let window = try base.makeWindow()
        window.showExample(request, base.example(1).id)

        try window.updateExample(request, base.example(2).id) { $0.name = "renamed" }

        #expect(try requestTab(window).shownExample == base.example(1))
    }

    @Test func `saving the Example in its own Tab refreshes the viewer`() throws {
        let window = try base.makeWindow()
        window.showExample(request, base.example(1).id)
        window.openExample(request, base.example(1).id)
        let editor = try #require(window.selectedTab)
        editor.tab.content = .example(base.example(1, name: "edited", status: 404))

        window.save(editor.tab.id)

        let shown = try requestTab(window).shownExample
        #expect(shown?.name == "edited" && shown?.status == 404)
    }

    @Test func `a change to the file from outside refreshes the viewer, and a deleted file empties it`() async throws {
        let window = try base.makeWindow()
        window.showExample(request, base.example(1).id)
        let tab = try requestTab(window)

        try base.put([base.example(1, name: "pulled"), base.example(2)])
        await base.deliver([base.path], to: window)
        #expect(tab.shownExample?.name == "pulled")

        try FileManager.default.removeItem(at: base.base.file)
        await base.deliver([base.path], to: window)
        #expect(tab.shownExample == nil)
    }

    @Test func `the shown Example is not in the Session: the Tab is saved as it was`() throws {
        let window = try base.makeWindow()
        window.showExample(request, base.example(1).id)

        let snapshot = try #require(window.session.tabs.first { $0.source == .request(request) })

        #expect(snapshot.content == .request(OpenRequestTests.charge.definition))
        #expect(snapshot.baseline == .request(OpenRequestTests.charge.definition))
    }
}

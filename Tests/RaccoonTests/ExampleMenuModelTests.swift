import AppKit
@testable import Raccoon
import RaccoonData
import RaccoonDomain
import RaccoonTesting
import Testing

/// New Example, Rename, Duplicate and Delete as the window does them, under the sidebar's menus (examples.md).
@MainActor
struct ExampleMenuModelTests {
    let open = OpenExampleTests()
    var request: RequestID { open.request }

    // MARK: newExample

    @Test func `newExample appends a 200 Example with an empty text body and opens its Tab after the selected one`() throws {
        let window = try open.makeWindow()
        window.openExample(request, open.example(1).id)
        let selectedBefore = try #require(window.selectedTab)

        let row = try window.newExample(request)

        let made = try #require(try open.onDisk().examples.last)
        #expect(try open.onDisk().examples.map(\.id) == [open.example(1).id, open.example(2).id, made.id])
        #expect(made == Example(id: made.id, name: "New Example", status: 200, headers: [], body: .text("")))
        let tab = try #require(window.selectedTab)
        #expect(tab.tab.source == .example(request, made.id))
        #expect(tab.tab.content == .example(made) && !tab.tab.isDirty)
        let at = try #require(window.tabs.firstIndex { $0 === selectedBefore })
        #expect(window.tabs[at + 1] === tab)
        #expect(row == "\(open.path)#\(made.id.rawValue.uuidString)")
    }

    @Test func `each New Example is a fresh id, so two make two rows and two Tabs`() throws {
        let window = try open.makeWindow([])

        _ = try window.newExample(request)
        _ = try window.newExample(request)

        let ids = try open.onDisk().examples.map(\.id)
        #expect(ids.count == 2 && Set(ids).count == 2)
        #expect(window.tabs.filter { $0.tab.example != nil }.count == 2)
    }

    @Test func `newExample for a Request that is not in the tree is requestGone and opens nothing`() throws {
        let window = try open.makeWindow()
        let tabs = window.tabs.count

        #expect(throws: ExampleWriteError.requestGone) { try window.newExample(RequestID(UUID())) }

        #expect(window.tabs.count == tabs)
        #expect(try open.onDisk().examples == [open.example(1), open.example(2)])
    }

    @Test func `newExample against an unreadable file writes nothing and opens no Tab`() throws {
        let window = try open.makeWindow()
        let garbage = Data("not json".utf8)
        try garbage.write(to: open.base.file)
        let tabs = window.tabs.count

        #expect(throws: ExampleWriteError.self) { try window.newExample(request) }

        #expect(try Data(contentsOf: open.base.file) == garbage)
        #expect(window.tabs.count == tabs)
    }

    @Test func `New Example leaves a Dirty Request Tab of the same Request as it was, and the Example Tab opens`() throws {
        let window = try open.makeWindow()
        window.openRequest(request)
        let requestTab = try #require(window.selectedTab)
        requestTab.tab.definition.method = "PUT"
        let (definition, baseline) = (requestTab.tab.definition, requestTab.tab.baseline)
        #expect(requestTab.tab.isDirty)

        _ = try window.newExample(request)

        #expect(requestTab.tab.definition == definition && requestTab.tab.baseline == baseline)
        #expect(requestTab.tab.isDirty && !requestTab.tab.isChangedOnDisk)
        #expect(window.selectedTab?.tab.example?.name == "New Example")
        #expect(window.tabs.contains { $0 === requestTab })
    }

    // MARK: duplicateExample

    @Test func `duplicateExample inserts the copy right after the original, with a new id, and opens no Tab`() throws {
        let window = try open.makeWindow([open.example(1), open.example(2, name: "second", status: 404)])
        window.openExample(request, open.example(1).id)
        let tabs = window.tabs.map(\.tab)

        let row = try window.duplicateExample(request, open.example(1).id)

        let file = try open.onDisk().examples
        #expect(file.map(\.name) == ["ok", "ok 2", "second"])
        #expect(file[0] == open.example(1) && file[2] == open.example(2, name: "second", status: 404))
        #expect(file[1].id != file[0].id && file[1].body == file[0].body && file[1].status == file[0].status)
        #expect(window.tabs.map(\.tab) == tabs)
        #expect(row == "\(open.path)#\(file[1].id.rawValue.uuidString)")
    }

    @Test func `duplicating the last Example puts the copy last`() throws {
        let window = try open.makeWindow()

        _ = try window.duplicateExample(request, open.example(2).id)

        #expect(try open.onDisk().examples.map(\.name) == ["ok", "ok", "ok 2"])
    }

    @Test func `duplicateExample of an Example the file lost writes nothing new and returns no row`() throws {
        let window = try open.makeWindow()

        let row = try window.duplicateExample(request, ExampleID(UUID()))

        #expect(row == nil)
        #expect(try open.onDisk().examples == [open.example(1), open.example(2)])
    }

    @Test func `duplicateExample against an unreadable file, or a missing Request, writes nothing and says why`() throws {
        let window = try open.makeWindow()
        #expect(throws: ExampleWriteError.requestGone) { try window.duplicateExample(RequestID(UUID()), open.example(1).id) }

        let garbage = Data("not json".utf8)
        try garbage.write(to: open.base.file)
        do {
            _ = try window.duplicateExample(request, open.example(1).id)
            Issue.record("did not throw")
        } catch {
            guard case .failed(let reason) = error else { Issue.record("wrong error \(error)"); return }
            #expect(!reason.isEmpty)
        }
        #expect(try Data(contentsOf: open.base.file) == garbage)
    }

    // MARK: Rename and Delete

    @Test func `a name may repeat: renaming to another Example's name keeps both, told apart by id`() throws {
        let window = try open.makeWindow([open.example(1, name: "one"), open.example(2, name: "two")])

        try window.updateExample(request, open.example(2).id) { $0.name = "one" }

        #expect(try open.onDisk().examples.map(\.name) == ["one", "one"])
        #expect(Set(try open.onDisk().examples.map(\.id)).count == 2)
    }

    @Test func `renaming an Example whose Tab is Dirty keeps its edits and is Changed on Disk against the file`() throws {
        let window = try open.makeWindow()
        window.openExample(request, open.example(1).id)
        let tab = try #require(window.selectedTab)
        let mine = Example(id: open.example(1).id, name: "mine", status: 200, body: .text("edited"))
        tab.tab.content = .example(mine)

        try window.updateExample(request, open.example(1).id) { $0.name = "renamed" }

        #expect(tab.tab.content == .example(mine) && tab.tab.isDirty)
        #expect(tab.tab.isChangedOnDisk)
        #expect(tab.tab.baseline == .example(open.example(1, name: "renamed")))
    }

    @Test func `deleting an Example open in a Tab keeps the Tab as Deleted on disk, and ⌘S appends it again`() throws {
        let (window, tab) = try open.openFirst()
        let working = Example(id: open.example(1).id, name: "mine", status: 200, body: .text("x"))
        tab.tab.content = .example(working)

        try window.removeExample(request, open.example(1).id)

        #expect(try open.onDisk().examples == [open.example(2)])
        #expect(window.tabs.contains { $0 === tab } && tab.tab.source == .example(request, open.example(1).id))
        #expect(tab.tab.content == .example(working))
        #expect(tab.tab.baseline == nil && tab.notice == .exampleDeletedOnDisk)

        window.save(tab.tab.id)

        #expect(try open.onDisk().examples == [open.example(2), working])
        #expect(tab.notice == nil && !tab.tab.isDirty)
    }

    @Test func `a failed delete removes nothing and leaves the Tab as it was`() throws {
        let (window, tab) = try open.openFirst()
        let folder = open.base.file.deletingLastPathComponent()
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: folder.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: folder.path) }

        #expect(throws: ExampleWriteError.self) { try window.removeExample(request, open.example(1).id) }

        #expect(try open.onDisk().examples == [open.example(1), open.example(2)])
        #expect(tab.notice == nil && tab.tab.baseline != nil)
    }
}

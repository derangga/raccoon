import AppKit
@testable import Raccoon
import RaccoonData
import RaccoonDomain
import RaccoonTesting
import Testing

/// Save as Example on a window: the received Response becomes an Example of its Request, over a
/// live store in a temp dir (examples.md).
@MainActor
struct SaveAsExampleTests {
    let base = SaveRequestTests()
    let request = OpenRequestTests.charge.id
    let path = "Payments API/Create charge.json"

    static let reply = Response(
        status: 201,
        headers: [.init(name: "Content-Encoding", value: "gzip"), .init(name: "Content-Type", value: "application/json")],
        body: Data(#"{"id":"ch_1"}"#.utf8), elapsed: .milliseconds(40), byteCount: 13)

    func onDisk() throws -> Request { try RequestFile.decode(Data(contentsOf: base.file)) }

    /// The Request Tab for Create charge, Dirty, holding `response`.
    func received(_ response: ResponseState = .received(reply)) throws -> (WindowModel, TabModel) {
        let (window, tab) = try base.openEdited()
        tab.tab.response = response
        return (window, tab)
    }

    func summaries(_ window: WindowModel) -> [ExampleSummary] {
        for collection in window.index.collections {
            for case .request(request, _, _, _, let examples) in Self.requests(collection.nodes) { return examples }
        }
        return []
    }

    static func requests(_ nodes: [TreeNode]) -> [TreeNode] {
        nodes.flatMap { node -> [TreeNode] in
            if case .folder(_, let children) = node { return requests(children) }
            return [node]
        }
    }

    @Test func `a received Response is written as an Example, named by its status line`() throws {
        let (window, tab) = try received()

        let row = window.saveAsExample(tab.tab.id)

        let saved = try #require(try onDisk().examples.first)
        #expect(try onDisk().examples.count == 1)
        #expect(saved.name == "201 Created")
        #expect(saved.status == 201)
        #expect(saved.headers == [Row(name: "Content-Type", value: "application/json")])
        #expect(saved.body == .text(#"{"id":"ch_1"}"#))
        #expect(row == path + "#" + saved.id.rawValue.uuidString)
        #expect(tab.exampleNote == nil)
    }

    @Test func `the Request Tab is not touched, so a Dirty Tab stays Dirty with its edits`() throws {
        let (window, tab) = try received()
        let definition = tab.tab.definition
        let baseline = tab.tab.baseline

        window.saveAsExample(tab.tab.id)

        #expect(tab.tab.isDirty)
        #expect(tab.tab.definition == definition)
        #expect(tab.tab.baseline == baseline)
        #expect(try onDisk().definition == OpenRequestTests.charge.definition)
        #expect(window.selectedTab === tab)
    }

    @Test func `the sidebar's index gains the Example row`() throws {
        let (window, tab) = try received()

        let row = window.saveAsExample(tab.tab.id)

        let listed = try #require(summaries(window).first)
        #expect(summaries(window).count == 1)
        #expect(listed.name == "201 Created" && listed.status == 201)
        #expect(row == listed.path(in: path))
    }

    @Test func `saving twice makes two Examples with their own ids`() throws {
        let (window, tab) = try received()

        let first = window.saveAsExample(tab.tab.id)
        let second = window.saveAsExample(tab.tab.id)

        let examples = try onDisk().examples
        #expect(examples.count == 2)
        #expect(examples[0].id != examples[1].id)
        #expect(first != nil && first != second)
    }

    @Test func `a Draft saves nothing`() throws {
        let (window, _) = try received()
        window.newTab()
        let draft = try #require(window.selectedTab)
        draft.tab.response = .received(Self.reply)
        let before = try Data(contentsOf: base.file)

        #expect(window.saveAsExample(draft.tab.id) == nil)

        #expect(try Data(contentsOf: base.file) == before)
        #expect(draft.exampleNote == nil)
    }

    @Test(arguments: [ResponseState.idle, .failed(.timedOut(seconds: 60), after: .seconds(60))])
    func `a Tab with no received Response saves nothing`(state: ResponseState) throws {
        let (window, tab) = try received(state)
        let before = try Data(contentsOf: base.file)

        #expect(window.saveAsExample(tab.tab.id) == nil)

        #expect(try Data(contentsOf: base.file) == before)
        #expect(tab.exampleNote == nil)
    }

    @Test func `an unreadable file is never written, and says so in the note`() throws {
        let (window, tab) = try received()
        let garbage = Data("not json".utf8)
        try garbage.write(to: base.file)

        #expect(window.saveAsExample(tab.tab.id) == nil)

        #expect(try Data(contentsOf: base.file) == garbage)
        let note = try #require(tab.exampleNote)
        #expect(note.hasPrefix("Couldn't save the Example: Not valid JSON at line 1."))
        #expect(note.hasSuffix("."))
        #expect(!note.hasSuffix(".."))
        #expect(tab.tab.isDirty)
    }

    @Test func `a Request with no file in the tree says it was deleted`() throws {
        let (window, tab) = try received()
        tab.tab.source = .request(RequestID(UUID()))

        #expect(window.saveAsExample(tab.tab.id) == nil)

        #expect(tab.exampleNote == "Couldn't save the Example: its Request was deleted.")
        #expect(try onDisk().examples.isEmpty)
    }

    @Test func `the next save that lands clears the note`() throws {
        let (window, tab) = try received()
        tab.exampleNote = "Couldn't save the Example: the disk is full."

        window.saveAsExample(tab.tab.id)

        #expect(tab.exampleNote == nil)
    }

    @Test func `the next send clears the note`() throws {
        let (_, tab) = try received()
        tab.exampleNote = "Couldn't save the Example: the disk is full."

        tab.send()

        #expect(tab.exampleNote == nil)
    }
}

/// Response ▸ Save as Example (⌥⌘E): the menu item, its validation, and what the app does with it.
@MainActor
struct SaveAsExampleMenuTests {
    let saving = SaveAsExampleTests()
    let theme = ThemeEnvironment(catalog: ThemeCatalog.load(), isDark: false)

    var item: NSMenuItem {
        get throws {
            let response = try #require(MainMenu.make(theme: .standalone()).item(withTitle: "Response")?.submenu)
            return try #require(response.item(withTitle: "Save as Example"))
        }
    }

    func delegate(_ window: WindowModel) -> AppDelegate {
        let delegate = AppDelegate()
        delegate.windowModel = window
        return delegate
    }

    @Test func `the Response menu has Save as Example on ⌥⌘E, for the app to take`() throws {
        let item = try item

        #expect(item.action == #selector(AppDelegate.saveAsExample(_:)))
        #expect(item.keyEquivalent == "e")
        #expect(item.keyEquivalentModifierMask == [.option, .command])
        #expect(item.target == nil)
    }

    @Test func `it is enabled on a Request Tab that holds a received Response`() throws {
        let (window, _) = try saving.received()

        #expect(delegate(window).validateMenuItem(try item))
    }

    @Test func `it is disabled on a Draft, with no Response, and with no Tab`() throws {
        let (window, _) = try saving.received(.idle)
        let delegate = delegate(window)
        let item = try item
        #expect(!delegate.validateMenuItem(item))

        window.newTab()
        window.selectedTab?.tab.response = .received(SaveAsExampleTests.reply)
        #expect(!delegate.validateMenuItem(item))

        #expect(!AppDelegate().validateMenuItem(item))
    }

    @Test func `choosing it saves the Example, opens the Request row and selects the new one`() throws {
        let (window, tab) = try saving.received()
        let sidebar = SidebarViewController(window: window, theme: theme, reveal: { _ in })
        sidebar.view.frame = NSRect(x: 0, y: 0, width: 232, height: 600)
        sidebar.outline.collapseItem(nil, collapseChildren: true)
        let delegate = delegate(window)
        delegate.sidebar = sidebar

        delegate.saveAsExample(nil)

        let saved = try #require(try saving.onDisk().examples.first)
        let row = saved.id.rawValue.uuidString
        let selected = (sidebar.outline.item(atRow: sidebar.outline.selectedRow) as? SidebarItem)
        #expect(selected?.path == saving.path + "#" + row)
        #expect(selected?.name == "201 Created")
        #expect(sidebar.item(path: saving.path).map(sidebar.outline.isItemExpanded) == true)
        #expect(tab.tab.isDirty)
        #expect(window.selectedTab === tab)
    }

    @Test func `choosing it on a Draft does nothing`() throws {
        let (window, _) = try saving.received()
        window.newTab()
        window.selectedTab?.tab.response = .received(SaveAsExampleTests.reply)
        let before = try Data(contentsOf: saving.base.file)

        delegate(window).saveAsExample(nil)

        #expect(try Data(contentsOf: saving.base.file) == before)
    }

    @Test func `choosing it with a sheet attached does nothing`() throws {
        let (window, _) = try saving.received()
        let controller = MainWindowController(theme: theme, inspector: InspectorMemory(), reduceMotion: { true })
        let delegate = delegate(window)
        delegate.windowController = controller
        let host = try #require(controller.window)
        host.beginSheet(NSWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 100), styleMask: [.titled], backing: .buffered, defer: false),
                        completionHandler: nil)
        let before = try Data(contentsOf: saving.base.file)

        delegate.saveAsExample(nil)

        #expect(try Data(contentsOf: saving.base.file) == before)
    }
}

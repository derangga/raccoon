import AppKit
@testable import Raccoon
import RaccoonDomain
import Testing

/// The toolbar item's words, as a function of the running servers (mock-server.md, Where it shows
/// that it runs), and the item over them. No window model: the servers are handed in.
@MainActor
struct MockToolbarItemTests {
    static func server(_ collection: String, _ port: UInt16) -> MockServer {
        MockServer(collection: collection, port: port, allowsCORS: true, routes: [])
    }

    @Test func `none running is not drawn`() {
        #expect(MockToolbarContent([]) == nil)
    }

    @Test func `one running reads Mock Server and its port, with the address in the tooltip`() throws {
        let content = try #require(MockToolbarContent([Self.server("Pets", 3000)]))
        #expect(content.title == "Mock Server")
        #expect(content.port == ":3000")
        #expect(content.tooltip == "Mock Server running on http://127.0.0.1:3000. Click to configure.")
        #expect(content.rows.isEmpty)
    }

    @Test func `two running read 2 Mock Servers, with a row per Collection in name order`() throws {
        let content = try #require(MockToolbarContent([Self.server("Pets", 3000), Self.server("Orders", 8081)]))
        #expect(content.title == "2 Mock Servers")
        #expect(content.port == nil)
        #expect(content.tooltip == "2 Mock Servers running. Click to choose one.")
        #expect(content.rows == [.init(collection: "Orders", port: ":8081"), .init(collection: "Pets", port: ":3000")])
    }

    @Test func `the count follows the servers`() throws {
        let three = (1...3).map { Self.server("C\($0)", 3000 + UInt16($0)) }
        #expect(MockToolbarContent(three)?.title == "3 Mock Servers")
        #expect(MockToolbarContent(three)?.tooltip == "3 Mock Servers running. Click to choose one.")
    }

    @Test func `a Collection row's tooltip names the address`() {
        #expect(MockToolbarContent.rowTooltip(Self.server("Pets", 3000)) == "Mock Server running on http://127.0.0.1:3000")
    }

    // MARK: the item

    func item() -> MockToolbarButton { MockToolbarButton() }

    @Test func `with none the button reports hidden`() {
        let button = item()
        var shown: [Bool] = []
        button.onShownChange = { shown.append($0) }

        button.show([])

        #expect(shown == [false])
    }

    @Test func `one server draws the button with its title, port and accessibility label`() {
        let button = item()
        var shown: [Bool] = []
        button.onShownChange = { shown.append($0) }

        button.show([Self.server("Pets", 3000)])

        #expect(shown == [true])
        #expect(button.attributedTitle.string == "Mock Server :3000")
        #expect(button.toolTip == "Mock Server running on http://127.0.0.1:3000. Click to configure.")
        #expect(button.accessibilityLabel() == button.toolTip)
    }

    @Test func `a click with one server opens its sheet`() {
        let button = item()
        var opened: [String] = []
        button.open = { opened.append($0) }
        button.show([Self.server("Pets", 3000)])

        button.performClick(nil)

        #expect(opened == ["Pets"])
    }

    @Test func `with several, the menu lists the Collections with their ports and a pick opens that sheet`() throws {
        let button = item()
        var opened: [String] = []
        button.open = { opened.append($0) }
        button.show([Self.server("Pets", 3000), Self.server("Orders", 8081)])

        let menu = button.choiceMenu(for: [Self.server("Pets", 3000), Self.server("Orders", 8081)])
        #expect(menu.items.map { $0.attributedTitle?.string } == ["Orders  :8081", "Pets  :3000"])
        let second = menu.items[1]
        _ = (second.target as? NSObject)?.perform(second.action, with: second)

        #expect(opened == ["Pets"])
    }

    @Test func `the toolbar item sits before the inspector toggle, hidden until a server runs and again when the last stops`() throws {
        let controller = MainWindowController(theme: ThemeController.standalone().theme, inspector: InspectorMemory(), reduceMotion: { true })
        let items = try #require(controller.window?.toolbar).items
        let mock = try #require(items.first { $0.itemIdentifier == MainWindowController.mockID })
        #expect(items.map(\.itemIdentifier).suffix(3) == [MainWindowController.environmentID, MainWindowController.mockID, MainWindowController.inspectorToggleID])
        #expect(mock.isHidden)

        controller.mockButton.show([Self.server("Pets", 3000)])
        #expect(!mock.isHidden)
        controller.mockButton.show([])
        #expect(mock.isHidden)
    }
}

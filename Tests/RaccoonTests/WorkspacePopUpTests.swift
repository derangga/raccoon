import AppKit
@testable import Raccoon
import Testing

@MainActor
struct WorkspacePopUpTests {
    func popUp(_ paths: [String], open: String) -> WorkspacePopUp {
        let popUp = WorkspacePopUp()
        popUp.reload(workspaces: paths, open: open)
        return popUp
    }

    @Test func `the title is the open Workspace's, its menu lists every Workspace sorted with the open one checked`() {
        let popUp = popUp(["/w/zeta", "/w/Alpha", "/w/beta"], open: "/w/beta")

        #expect(popUp.title == "beta")
        let items = popUp.menu?.items ?? []
        #expect(items.map(\.title) == ["Alpha", "beta", "zeta", "", "New Workspace…", "Open Workspace…", "Remove from List"])
        #expect(items.map(\.state) == [.off, .on, .off, .off, .off, .off, .off])
        #expect(items[3].isSeparatorItem)
        #expect(items.prefix(3).map(\.toolTip) == ["/w/Alpha", "/w/beta", "/w/zeta"])
    }

    @Test func `a tooltip abbreviates the home folder with a tilde`() {
        let home = NSHomeDirectory()
        let popUp = popUp([home + "/Raccoon"], open: home + "/Raccoon")
        #expect(popUp.menu?.items[0].toolTip == "~/Raccoon")
    }

    @Test func `two Workspaces with one folder name show their parent folder`() {
        let popUp = popUp(["/work/api", "/side/api", "/work/web"], open: "/side/api")
        #expect(popUp.title == "api — side")
        #expect(popUp.menu?.items.prefix(3).map(\.title) == ["api — side", "api — work", "web"])
    }

    @Test func `Remove from List holds every Workspace but the open one`() throws {
        let popUp = popUp(["/w/a", "/w/b", "/w/c"], open: "/w/b")
        let remove = try #require(popUp.menu?.items.last)
        #expect(remove.submenu?.items.map(\.title) == ["a", "c"])
        #expect(remove.isEnabled)
    }

    @Test func `with one Workspace the menu has its row and Remove from List is disabled`() throws {
        let popUp = popUp(["/w/Raccoon"], open: "/w/Raccoon")
        let remove = try #require(popUp.menu?.items.last)
        #expect(popUp.menu?.items.map(\.title) == ["Raccoon", "", "New Workspace…", "Open Workspace…", "Remove from List"])
        #expect(!remove.isEnabled)
        #expect(remove.submenu?.items.isEmpty == true)
    }

    @Test func `the items call back, and the pop-up keeps showing the open Workspace`() throws {
        let popUp = popUp(["/w/a", "/w/b"], open: "/w/a")
        var calls: [String] = []
        popUp.onSwitch = { calls.append("switch \($0)") }
        popUp.onNew = { calls.append("new") }
        popUp.onOpen = { calls.append("open") }
        popUp.onRemove = { calls.append("remove \($0)") }
        let menu = try #require(popUp.menu)

        menu.performActionForItem(at: 1)
        menu.performActionForItem(at: 3)
        menu.performActionForItem(at: 4)
        let submenu = try #require(menu.items[5].submenu)
        submenu.performActionForItem(at: 0)

        #expect(calls == ["switch /w/b", "new", "open", "remove /w/b"])
        #expect(popUp.title == "a")
    }

    @Test func `a 120-character name end-truncates in the pop-up and shows whole in the menu`() {
        let long = String(repeating: "n", count: 120)
        let popUp = popUp(["/w/" + long, "/w/b"], open: "/w/" + long)
        popUp.frame = NSRect(x: 0, y: 0, width: 212, height: 24)

        #expect(popUp.title == long)
        #expect((popUp.cell as? NSPopUpButtonCell)?.lineBreakMode == .byTruncatingTail)
        #expect(popUp.menu?.items.first { $0.title == long } != nil)
    }
}

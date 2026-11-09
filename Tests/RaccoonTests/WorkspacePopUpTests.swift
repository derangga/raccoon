import AppKit
@testable import Raccoon
import Testing

@MainActor
struct WorkspacePopUpTests {
    func popUp(_ paths: [String], open: String) -> WorkspacePopUp {
        let popUp = WorkspacePopUp(theme: ThemeController.standalone().theme)
        popUp.reload(workspaces: paths, open: open)
        return popUp
    }

    @Test func `the title is the open Workspace's, its rows list every Workspace sorted with the open one chosen`() {
        let popUp = popUp(["/w/zeta", "/w/Alpha", "/w/beta"], open: "/w/beta")

        #expect(popUp.title == "beta")
        #expect(popUp.entries == [
            .option(id: "/w/Alpha", title: "Alpha", detail: "/w/Alpha", isChosen: false),
            .option(id: "/w/beta", title: "beta", detail: "/w/beta", isChosen: true),
            .option(id: "/w/zeta", title: "zeta", detail: "/w/zeta", isChosen: false),
            .separator,
            .action(id: "new", title: "New Workspace…"),
            .action(id: "open", title: "Open Workspace…"),
            .action(id: "manage", title: "Manage Workspaces…"),
        ])
    }

    @Test func `a detail line abbreviates the home folder with a tilde`() {
        let home = NSHomeDirectory()
        let popUp = popUp([home + "/Raccoon"], open: home + "/Raccoon")
        #expect(popUp.entries.first == .option(id: home + "/Raccoon", title: "Raccoon", detail: "~/Raccoon", isChosen: true))
    }

    @Test func `two Workspaces with one folder name show their parent folder`() {
        let popUp = popUp(["/work/api", "/side/api", "/work/web"], open: "/side/api")
        #expect(popUp.title == "api — side")
        let titles = popUp.entries.prefix(3).compactMap { entry -> String? in
            if case let .option(_, title, _, _) = entry { title } else { nil }
        }
        #expect(titles == ["api — side", "api — work", "web"])
    }

    @Test func `with one Workspace the list has its row and Manage Workspaces… stays`() {
        let popUp = popUp(["/w/Raccoon"], open: "/w/Raccoon")
        #expect(popUp.entries.count == 5)
        #expect(popUp.entries.last == .action(id: "manage", title: "Manage Workspaces…"))
    }

    @Test func `the rows call back, and the title stays on the open Workspace`() {
        let popUp = popUp(["/w/a", "/w/b"], open: "/w/a")
        var calls: [String] = []
        popUp.onSwitch = { calls.append("switch \($0)") }
        popUp.onNew = { calls.append("new") }
        popUp.onOpen = { calls.append("open") }
        popUp.onManage = { calls.append("manage") }

        popUp.onPick(.option("/w/b"))
        popUp.onPick(.action("new"))
        popUp.onPick(.action("open"))
        popUp.onPick(.action("manage"))

        #expect(calls == ["switch /w/b", "new", "open", "manage"])
        #expect(popUp.title == "a")
    }

    @Test func `a 120-character name is the title whole, for the trigger to end-truncate`() {
        let long = String(repeating: "n", count: 120)
        let popUp = popUp(["/w/" + long, "/w/b"], open: "/w/" + long)
        popUp.frame = NSRect(x: 0, y: 0, width: 212, height: 24)

        #expect(popUp.title == long)
        #expect(popUp.entries.contains(.option(id: "/w/" + long, title: long, detail: "/w/" + long, isChosen: true)))
    }
}

import AppKit
@testable import Raccoon
import RaccoonData
import RaccoonDomain
import RaccoonTesting
import Testing

/// The toolbar's Environment pop-up over a window loaded from a temp Data Folder.
@MainActor
struct EnvironmentPickerTests {
    let temp = FileManager.default.temporaryDirectory.appending(path: "raccoon-\(UUID())")
    var root: URL { temp.appending(path: "Raccoon") }

    func makeWindow(environments: [String]) throws -> WindowModel {
        for name in environments {
            let url = root.appending(path: "environments/\(name).json")
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try EnvironmentFile.encode([]).write(to: url)
        }
        let window = WindowModel(
            dataFolder: .test(root), folderWatch: ManualFolderWatch(),
            sessionStore: DiskSessionStore(directory: temp.appending(path: "Support"), root: root.path),
            secrets: InMemorySecretStore(), instants: FixedInstantSource(.now),
            makeTab: {
                TabModel(transport: ScriptedTransport(.failure(.timedOut(seconds: 60))), secrets: InMemorySecretStore(), files: DictionaryFileReading([:]),
                         instants: FixedInstantSource(.now), clipboard: RecordingClipboardWriter())
            }
        )
        window.loadDataFolder()
        return window
    }

    @Test func `the rows are No Environment, each Environment, then Edit Environments…, and the active one is chosen`() async throws {
        let window = try makeWindow(environments: ["Prod", "Dev"])
        let picker = EnvironmentPicker(theme: ThemeController.standalone().theme)
        picker.bind(window)

        #expect(picker.entries == [
            .option(id: "none", title: "No Environment", detail: nil, isChosen: true),
            .separator,
            .option(id: "env:Dev", title: "Dev", detail: nil, isChosen: false),
            .option(id: "env:Prod", title: "Prod", detail: nil, isChosen: false),
            .separator,
            .action(id: "edit", title: "Edit Environments…"),
        ])
        #expect(picker.title == "No Environment")

        window.pickActiveEnvironment("Prod")
        for _ in 0..<100 where picker.title != "Prod" { await Task.yield() }
        #expect(picker.title == "Prod")
        #expect(picker.entries[3] == .option(id: "env:Prod", title: "Prod", detail: nil, isChosen: true))
    }

    @Test func `picking a row sets the window's Active Environment, and No Environment clears it`() throws {
        let window = try makeWindow(environments: ["Dev", "Prod"])
        let picker = EnvironmentPicker(theme: ThemeController.standalone().theme)
        picker.bind(window)

        picker.onPick(.option("env:Dev"))
        #expect(window.activeEnvironment == "Dev")
        picker.onPick(.option("none"))
        #expect(window.activeEnvironment == nil)
    }

    @Test func `an Environment named none is not No Environment`() throws {
        let window = try makeWindow(environments: ["none"])
        let picker = EnvironmentPicker(theme: ThemeController.standalone().theme)
        picker.bind(window)

        picker.onPick(.option("env:none"))
        #expect(window.activeEnvironment == "none")
    }

    @Test func `a long Environment name truncates at 200 pt and shows in full in the list`() throws {
        let long = String(repeating: "Payments sandbox for EU tenants ", count: 3)
        let window = try makeWindow(environments: [long])
        let picker = EnvironmentPicker(theme: ThemeController.standalone().theme)
        picker.bind(window)
        window.pickActiveEnvironment(long)
        picker.bind(window)

        #expect(picker.fittingWidth == 200)
        #expect(picker.entries.contains(.option(id: "env:" + long, title: long, detail: nil, isChosen: true)))
    }

    @Test func `a short title sizes the picker to its text`() throws {
        let picker = EnvironmentPicker(theme: ThemeController.standalone().theme)
        picker.bind(try makeWindow(environments: []))
        #expect(picker.fittingWidth > 60 && picker.fittingWidth < 200)
    }

    @Test func `Edit Environments… opens the sheet and leaves the choice showing`() throws {
        let window = try makeWindow(environments: ["Dev"])
        window.pickActiveEnvironment("Dev")
        let picker = EnvironmentPicker(theme: ThemeController.standalone().theme)
        picker.bind(window)
        var opened = 0
        picker.onEdit = { opened += 1 }

        picker.onPick(.action("edit"))

        #expect(opened == 1)
        #expect(picker.title == "Dev")
    }

    @Test func `⌃E in the View menu opens the picker`() throws {
        let view = try #require(MainMenu.make(theme: .standalone()).item(withTitle: "View")?.submenu)
        let item = try #require(view.item(withTitle: "Choose Environment"))
        #expect(item.keyEquivalent == "e" && item.keyEquivalentModifierMask == .control)
        #expect(item.action == #selector(AppDelegate.chooseEnvironment(_:)))
    }

    @Test func `the toolbar carries the picker before the inspector toggle`() {
        let controller = MainWindowController(theme: ThemeController.standalone().theme, inspector: InspectorMemory(), reduceMotion: { false })
        let ids = controller.toolbarDefaultItemIdentifiers(NSToolbar())
        #expect(ids.suffix(2) == [MainWindowController.environmentID, MainWindowController.inspectorToggleID])
    }
}

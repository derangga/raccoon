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
                TabModel(transport: ScriptedTransport(.failure(.timedOut)), secrets: InMemorySecretStore(), files: DictionaryFileReading([:]),
                         instants: FixedInstantSource(.now), clipboard: RecordingClipboardWriter())
            }
        )
        window.loadDataFolder()
        return window
    }

    @Test func `the menu is No Environment, each Environment, then Edit Environments…, and shows the active one`() async throws {
        let window = try makeWindow(environments: ["Prod", "Dev"])
        let picker = EnvironmentPicker()
        picker.bind(window)

        #expect(picker.itemArray.map { $0.isSeparatorItem ? "-" : $0.title } == ["No Environment", "-", "Dev", "Prod", "-", "Edit Environments…"])
        #expect(picker.titleOfSelectedItem == "No Environment")

        window.pickActiveEnvironment("Prod")
        for _ in 0..<100 where picker.titleOfSelectedItem != "Prod" { await Task.yield() }
        #expect(picker.titleOfSelectedItem == "Prod")
        #expect(picker.selectedItem?.state == .on)
    }

    @Test func `picking an item sets the window's Active Environment, and No Environment clears it`() throws {
        let window = try makeWindow(environments: ["Dev", "Prod"])
        let picker = EnvironmentPicker()
        picker.bind(window)

        picker.pick(try #require(picker.item(withTitle: "Dev")))
        #expect(window.activeEnvironment == "Dev")
        picker.pick(try #require(picker.item(withTitle: "No Environment")))
        #expect(window.activeEnvironment == nil)
    }

    @Test func `a long Environment name truncates at 200 pt and shows in full in the menu`() throws {
        let long = String(repeating: "Payments sandbox for EU tenants ", count: 3)
        let window = try makeWindow(environments: [long])
        let picker = EnvironmentPicker()
        picker.bind(window)
        window.pickActiveEnvironment(long)
        picker.bind(window)

        picker.layoutSubtreeIfNeeded()
        #expect(picker.fittingSize.width <= 200)
        #expect(picker.item(withTitle: long) != nil)
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

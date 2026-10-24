import AppKit
@testable import Raccoon
import RaccoonData
import RaccoonDomain
import RaccoonTesting
import Testing

/// The inspector's open state, width and pane across relaunch (design-system §9 Q14).
@MainActor
struct InspectorMemoryTests {
    let temp = FileManager.default.temporaryDirectory.appending(path: "raccoon-\(UUID())")
    let theme = ThemeEnvironment(catalog: ThemeCatalog.load(), isDark: false)
    var sessionStore: DiskSessionStore { DiskSessionStore(directory: temp.appending(path: "Support"), root: temp.appending(path: "Raccoon").path) }

    /// A UserDefaults suite of its own per test, emptied first.
    func defaults(_ name: String = #function) -> UserDefaults {
        let suite = "InspectorMemoryTests.\(name)"
        UserDefaults().removePersistentDomain(forName: suite)
        return UserDefaults(suiteName: suite)!
    }

    @Test func `what is remembered is read back after a relaunch`() {
        let defaults = defaults()
        let memory = CompositionRoot.inspectorMemory(defaults: defaults)
        memory.rememberShown(true)
        memory.rememberWidth(320)
        memory.rememberPane("Curl")

        let relaunched = CompositionRoot.inspectorMemory(defaults: defaults)
        #expect(relaunched.isShown && relaunched.width == 320 && relaunched.pane == "Curl")
    }

    @Test func `nothing remembered, or values of the wrong type, read as closed with no width or pane`() {
        let empty = CompositionRoot.inspectorMemory(defaults: defaults())
        #expect(!empty.isShown && empty.width == nil && empty.pane == nil)

        let defaults = defaults("wrong types")
        defaults.set("yes", forKey: "InspectorShown")
        defaults.set(Double.nan, forKey: "InspectorWidth")
        defaults.set(1, forKey: "InspectorPane")
        let wrong = CompositionRoot.inspectorMemory(defaults: defaults)
        #expect(!wrong.isShown && wrong.width == nil && wrong.pane == nil)
    }

    func window(_ memory: InspectorMemory, width: CGFloat = 1200) -> MainWindowController {
        let controller = MainWindowController(theme: theme, inspector: memory, reduceMotion: { true })
        controller.window!.setContentSize(NSSize(width: width, height: 700))
        controller.window!.layoutIfNeeded()
        return controller
    }

    @Test(arguments: [(320, 320), (1000, 400), (100, 240)] as [(CGFloat, CGFloat)])
    func `remembered open, the inspector opens at the remembered width, kept within 240–400`(remembered: CGFloat, width: CGFloat) {
        let split = window(InspectorMemory(isShown: true, width: remembered)).split
        #expect(split.isInspectorShown && !split.inspectorItem.isCollapsed)
        #expect(split.inspectorItem.viewController.view.frame.width == width)
    }

    @Test func `remembered open in a window too narrow to dock it, the inspector overlays`() {
        let split = window(InspectorMemory(isShown: true, width: 400), width: 760).split
        #expect(split.isInspectorShown && split.isInspectorOverlaid)
    }

    @Test func `nothing remembered, the inspector stays closed`() {
        let split = window(InspectorMemory()).split
        #expect(!split.isInspectorShown && split.inspectorItem.isCollapsed)
    }

    @Test func `opening, closing and dragging the inspector's divider are each remembered`() {
        let defaults = defaults()
        let controller = window(CompositionRoot.inspectorMemory(defaults: defaults))
        let split = controller.split
        split.toggleInspector(nil)
        #expect(CompositionRoot.inspectorMemory(defaults: defaults).isShown)

        split.splitView.setPosition(1200 - 320, ofDividerAt: 1)
        controller.window!.layoutIfNeeded()
        #expect(split.inspectorItem.viewController.view.frame.width == 320)
        #expect(CompositionRoot.inspectorMemory(defaults: defaults).width == 320)

        split.toggleInspector(nil)
        let closed = CompositionRoot.inspectorMemory(defaults: defaults)
        #expect(!closed.isShown && closed.width == 320)
    }

    func makeWindow() -> WindowModel {
        WindowModel(
            dataFolder: .test(temp.appending(path: "Raccoon")), folderWatch: ManualFolderWatch(),
            sessionStore: sessionStore, secrets: InMemorySecretStore(), instants: FixedInstantSource(.now),
            makeTab: {
                TabModel(transport: ScriptedTransport(.failure(.timedOut)), secrets: InMemorySecretStore(), files: DictionaryFileReading([:]),
                         instants: FixedInstantSource(.now), clipboard: RecordingClipboardWriter())
            }
        )
    }

    @Test(arguments: [("Curl", 1), ("Variables", 0), ("Headers", 0), (nil, 0)] as [(String?, Int)])
    func `the inspector opens on the remembered pane, Variables when it names none`(pane: String?, segment: Int) {
        let inspector = InspectorViewController(window: makeWindow(), theme: theme, memory: InspectorMemory(pane: pane))
        #expect(inspector.paneSwitch.selectedSegment == segment)
        #expect(inspector.paneTitle.stringValue == ["Variables", "Curl"][segment])
        #expect(inspector.curl.isHidden == (segment == 0))
    }

    @Test func `the pane picked is remembered`() {
        let defaults = defaults()
        let inspector = InspectorViewController(window: makeWindow(), theme: theme, memory: CompositionRoot.inspectorMemory(defaults: defaults))
        inspector.showPane(1)
        #expect(CompositionRoot.inspectorMemory(defaults: defaults).pane == "Curl")
        inspector.showPane(0)
        #expect(CompositionRoot.inspectorMemory(defaults: defaults).pane == "Variables")
    }

    @Test func `quit with the Curl pane open at 320 pt, relaunch shows the same, and the Session file is not written`() async throws {
        let defaults = defaults()
        let model = makeWindow()
        let controller = window(CompositionRoot.inspectorMemory(defaults: defaults))
        let inspector = InspectorViewController(window: model, theme: theme, memory: CompositionRoot.inspectorMemory(defaults: defaults))
        controller.split.showInspector(inspector)
        controller.split.toggleInspector(nil)
        controller.split.splitView.setPosition(1200 - 320, ofDividerAt: 1)
        inspector.showPane(1)
        for _ in 0..<20 { await Task.yield() }
        #expect(try sessionStore.read() == nil)

        let relaunched = window(CompositionRoot.inspectorMemory(defaults: defaults)).split
        let relaunchedInspector = InspectorViewController(window: makeWindow(), theme: theme, memory: CompositionRoot.inspectorMemory(defaults: defaults))
        #expect(relaunched.isInspectorShown && relaunched.inspectorItem.viewController.view.frame.width == 320)
        #expect(relaunchedInspector.paneTitle.stringValue == "Curl")
    }
}

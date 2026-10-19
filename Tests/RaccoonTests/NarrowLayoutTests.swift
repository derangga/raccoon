import AppKit
@testable import Raccoon
import Testing

@MainActor
struct NarrowLayoutTests {
    let controller = MainWindowController(theme: ThemeEnvironment(catalog: ThemeCatalog.load(), isDark: false), reduceMotion: { true })
    var split: MainSplitViewController { controller.split }
    var window: NSWindow { controller.window! }

    func resize(width: CGFloat) {
        window.setContentSize(NSSize(width: width, height: 700))
        window.layoutIfNeeded()
    }

    func press(keyCode: UInt16, characters: String) -> NSEvent {
        NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber,
                         context: nil, characters: characters, charactersIgnoringModifiers: characters, isARepeat: false, keyCode: keyCode)!
    }

    func click(atX x: CGFloat) -> NSEvent {
        NSEvent.mouseEvent(with: .leftMouseDown, location: NSPoint(x: x, y: 100), modifierFlags: [], timestamp: 0,
                           windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
    }

    @Test func `the window cannot be smaller than 760 × 480`() {
        #expect(window.contentMinSize == NSSize(width: 760, height: 480))
    }

    @Test func `below 960 pt the sidebar collapses and its toggle opens it as an overlay`() {
        resize(width: 900)
        #expect(split.sidebarItem.isCollapsed)
        #expect(!split.isSidebarShown)
        #expect(controller.sidebarToggle.state == .off)

        split.toggleSidebar(nil)
        #expect(split.sidebarItem.isCollapsed)
        #expect(split.isSidebarOverlaid)
        #expect(controller.sidebarToggle.state == .on)

        resize(width: 1200)
        #expect(!split.sidebarItem.isCollapsed)
        #expect(!split.isSidebarOverlaid)
        #expect(controller.sidebarToggle.state == .on)
    }

    @Test func `a sidebar the user closed stays closed after the window widens again`() {
        resize(width: 1200)
        split.sidebarItem.isCollapsed = true
        resize(width: 900)
        resize(width: 1200)
        #expect(split.sidebarItem.isCollapsed)
    }

    @Test func `the inspector docks while the editor keeps 480 pt and overlays when it would not`() {
        resize(width: 1200)
        split.toggleInspector(nil)
        #expect(!split.inspectorItem.isCollapsed)
        #expect(controller.inspectorToggle.state == .on)

        resize(width: 970)  // 970 - 232 sidebar - 280 inspector leaves under 480
        #expect(split.inspectorItem.isCollapsed)
        #expect(split.isInspectorOverlaid)
        #expect(controller.inspectorToggle.state == .on)

        resize(width: 1200)
        #expect(!split.inspectorItem.isCollapsed)
        #expect(!split.isInspectorOverlaid)
    }

    @Test func `an overlaid inspector closes on Esc`() {
        resize(width: 970)
        split.toggleInspector(nil)
        #expect(split.isInspectorOverlaid)

        #expect(split.handleOverlayEvent(press(keyCode: 53, characters: "\u{1b}")) == nil)
        #expect(!split.isInspectorOverlaid)
        #expect(!split.isInspectorShown)
        #expect(controller.inspectorToggle.state == .off)
    }

    @Test func `typing leaves an overlaid inspector open`() {
        resize(width: 970)
        split.toggleInspector(nil)
        let key = press(keyCode: 0, characters: "a")
        #expect(split.handleOverlayEvent(key) === key)
        #expect(split.isInspectorOverlaid)
    }

    @Test func `an overlaid inspector closes on a click in the content, not on a click inside it`() {
        resize(width: 970)
        split.toggleInspector(nil)

        let inside = click(atX: 960)
        #expect(split.handleOverlayEvent(inside) === inside)
        #expect(split.isInspectorOverlaid)

        let content = click(atX: 500)
        #expect(split.handleOverlayEvent(content) === content)
        #expect(!split.isInspectorOverlaid)
    }

    @Test func `toggling an overlaid inspector closes it`() {
        resize(width: 970)
        split.toggleInspector(nil)
        split.toggleInspector(nil)
        #expect(!split.isInspectorOverlaid)
        #expect(split.inspectorItem.isCollapsed)
    }
}

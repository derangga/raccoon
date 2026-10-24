import AppKit
@testable import Raccoon
import Testing

@MainActor
struct NarrowLayoutTests {
    let controller = MainWindowController(theme: ThemeEnvironment(catalog: ThemeCatalog.load(), isDark: false), inspector: InspectorMemory(), reduceMotion: { true })
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

    /// The View menu item's title after AppKit validates it against the split.
    func title(_ action: Selector) -> String {
        let item = NSMenuItem(title: "", action: action, keyEquivalent: "")
        _ = split.validateUserInterfaceItem(item)
        return item.title
    }

    @Test func `the View menu says Hide while a pane is open, docked or overlaid`() {
        let (sidebar, inspector) = (#selector(NSSplitViewController.toggleSidebar(_:)), #selector(NSSplitViewController.toggleInspector(_:)))
        resize(width: 1200)
        #expect((title(sidebar), title(inspector)) == ("Hide Sidebar", "Show Inspector"))
        split.toggleInspector(nil)
        #expect(title(inspector) == "Hide Inspector")

        resize(width: 960)
        #expect(split.isInspectorOverlaid)
        #expect(title(inspector) == "Hide Inspector")

        resize(width: 900)
        #expect(title(sidebar) == "Show Sidebar")
        split.toggleSidebar(nil)
        #expect(split.isSidebarOverlaid)
        #expect(title(sidebar) == "Hide Sidebar")
    }

    @Test func `revealing the sidebar opens it, docked or overlaid, and never closes an open one`() {
        resize(width: 1200)
        split.sidebarItem.isCollapsed = true
        split.revealSidebar()
        #expect(!split.sidebarItem.isCollapsed && split.isSidebarShown)
        split.revealSidebar()
        #expect(!split.sidebarItem.isCollapsed)

        resize(width: 900)
        split.revealSidebar()
        #expect(split.isSidebarOverlaid)
        split.revealSidebar()
        #expect(split.isSidebarOverlaid)
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

    @Test func `showing the inspector opens it, docked or overlaid, and never closes an open one`() {
        resize(width: 1200)
        split.showInspector()
        #expect(!split.inspectorItem.isCollapsed && controller.inspectorToggle.state == .on)
        split.showInspector()
        #expect(split.isInspectorShown)

        split.toggleInspector(nil)
        resize(width: 970)  // beside the sidebar, the editor would keep under 480
        split.showInspector()
        #expect(split.isInspectorOverlaid && controller.inspectorToggle.state == .on)
    }

    @Test func `the inspector pane shows the controller it is given`() {
        let child = NSViewController()
        child.view = NSView()
        split.showInspector(child)
        #expect(child.parent != nil && child.view.superview != nil)
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

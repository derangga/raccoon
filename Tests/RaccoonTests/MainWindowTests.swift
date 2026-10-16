import AppKit
@testable import Raccoon
import Testing

@MainActor
struct MainWindowTests {
    let controller = MainWindowController(theme: ThemeEnvironment(catalog: ThemeCatalog.load(), isDark: false))
    var split: MainSplitViewController { controller.split }

    @Test func `the window opens with a 232 pt sidebar, the content and a closed inspector`() throws {
        let window = try #require(controller.window)
        window.layoutIfNeeded()
        let (sidebar, inspector) = (split.sidebarItem, split.inspectorItem)

        #expect(split.splitViewItems.count == 3)
        #expect(sidebar.behavior == .sidebar)
        #expect(!sidebar.isCollapsed)
        #expect(sidebar.viewController.view.frame.width == 232)
        #expect((sidebar.minimumThickness, sidebar.maximumThickness) == (180, 360))
        #expect(inspector.behavior == .inspector)
        #expect(inspector.isCollapsed)
        #expect((inspector.minimumThickness, inspector.maximumThickness) == (240, 400))
    }

    @Test func `the inspector opens at 280 pt`() throws {
        let window = try #require(controller.window)
        split.toggleInspector(nil)
        window.layoutIfNeeded()
        #expect(split.inspectorItem.viewController.view.frame.width == 280)
    }

    @Test func `each toggle is pressed exactly while its pane is open`() {
        #expect(controller.sidebarToggle.state == .on)
        #expect(controller.inspectorToggle.state == .off)

        split.toggleInspector(nil)
        split.sidebarItem.isCollapsed = true

        #expect(controller.inspectorToggle.state == .on)
        #expect(controller.sidebarToggle.state == .off)
    }

    @Test func `the toggles and the View menu use the split view controller's own actions`() throws {
        #expect(controller.sidebarToggle.action == #selector(NSSplitViewController.toggleSidebar(_:)))
        #expect(controller.inspectorToggle.action == #selector(NSSplitViewController.toggleInspector(_:)))
        #expect(controller.sidebarToggle.image?.accessibilityDescription == "Show Sidebar")
        #expect(controller.inspectorToggle.image?.accessibilityDescription == "Show Inspector")

        let view = try #require(MainMenu.make().item(withTitle: "View")?.submenu)
        #expect(view.item(withTitle: "Show Sidebar")?.action == #selector(NSSplitViewController.toggleSidebar(_:)))
        #expect(view.item(withTitle: "Show Inspector")?.action == #selector(NSSplitViewController.toggleInspector(_:)))
    }
}

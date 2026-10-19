import AppKit
@testable import Raccoon
import Testing

@MainActor
struct MainWindowTests {
    let controller = MainWindowController(theme: ThemeEnvironment(catalog: ThemeCatalog.load(), isDark: false), reduceMotion: { true })
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

    @Test func `the toolbar spans the whole window, above the sidebar and the inspector`() throws {
        let window = try #require(controller.window)
        #expect(!split.sidebarItem.allowsFullHeightLayout)
        #expect(!split.inspectorItem.allowsFullHeightLayout)
        #expect(!window.styleMask.contains(.fullSizeContentView))
        #expect(window.titlebarSeparatorStyle == .line)
        // Board 01 reads: traffic lights, sidebar toggle, the title, then the trailing items.
        #expect(window.titleVisibility == .hidden)
        #expect(window.title == "Raccoon")
        let items = try #require(window.toolbar).items
        #expect(items.map(\.itemIdentifier).prefix(2) == [MainWindowController.sidebarToggleID, MainWindowController.titleID])
        #expect((items[1].view as? NSTextField)?.stringValue == "Raccoon")
        #expect(items.last?.itemIdentifier == MainWindowController.inspectorToggleID)
    }

    @Test func `dividers take no width, so the window background never shows between panes`() throws {
        try #require(controller.window).layoutIfNeeded()
        #expect(split.splitView.dividerThickness == 0)
        let sidebar = split.sidebarItem.viewController.view
        let content = split.contentItem.viewController.view
        let (sidebarFrame, contentFrame) = (sidebar.convert(sidebar.bounds, to: split.splitView), content.convert(content.bounds, to: split.splitView))
        #expect(contentFrame.minX == sidebarFrame.maxX, "\(sidebarFrame) \(contentFrame)")
    }

    @Test func `the sidebar draws its own separator on its trailing edge`() throws {
        try #require(controller.window).layoutIfNeeded()
        let sidebar = split.sidebarItem.viewController.view
        let separator = try #require(sidebar.subviews.first { $0.frame.width == 1 })
        #expect(separator.frame.maxX == sidebar.bounds.maxX)
        #expect(separator.frame.height == sidebar.bounds.height)
    }

    @Test func `a zero-width divider still has a 6 pt drag area`() throws {
        try #require(controller.window).layoutIfNeeded()
        let drawn = NSRect(x: 232, y: 0, width: 0, height: 600)
        let effective = split.splitView(split.splitView, effectiveRect: drawn, forDrawnRect: drawn, ofDividerAt: 0)
        #expect(effective == NSRect(x: 229, y: 0, width: 6, height: 600))
    }

    @Test func `the sidebar is opaque, so focus never lets the desktop show through`() throws {
        try #require(controller.window).layoutIfNeeded()
        let sidebar = split.sidebarItem.viewController.view
        let background = try #require(sidebar.subviews.first { $0 is SidebarBackground })
        #expect(background.isOpaque)
        #expect(background.frame == sidebar.bounds)
        #expect(!sidebar.subviews.contains { $0 is NSVisualEffectView })
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

        let view = try #require(MainMenu.make(theme: .standalone()).item(withTitle: "View")?.submenu)
        #expect(view.item(withTitle: "Show Sidebar")?.action == #selector(NSSplitViewController.toggleSidebar(_:)))
        #expect(view.item(withTitle: "Show Inspector")?.action == #selector(NSSplitViewController.toggleInspector(_:)))
    }
}

@MainActor
struct EditMenuTests {
    @Test func `the Edit menu sends Select All, Cut, Copy and Paste to the first responder`() throws {
        let edit = try #require(MainMenu.make(theme: .standalone()).item(withTitle: "Edit")?.submenu)
        let all = try #require(edit.item(withTitle: "Select All"))
        #expect(all.keyEquivalent == "a" && all.keyEquivalentModifierMask == .command && all.target == nil)
        #expect(all.action == #selector(NSText.selectAll(_:)))
        #expect(edit.item(withTitle: "Cut")?.action == #selector(NSText.cut(_:)))
        #expect(edit.item(withTitle: "Copy")?.action == #selector(NSText.copy(_:)))
        #expect(edit.item(withTitle: "Paste")?.action == #selector(NSText.paste(_:)))
        #expect(edit.item(withTitle: "Redo")?.keyEquivalentModifierMask == [.command, .shift])
    }
}

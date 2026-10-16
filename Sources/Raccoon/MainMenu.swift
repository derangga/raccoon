import AppKit

/// The menu bar. Edit and the other menus arrive with the features that need them.
enum MainMenu {
    static func make() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(submenu("Raccoon", [
            NSMenuItem(title: "Hide Raccoon", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h"),
            .separator(),
            NSMenuItem(title: "Quit Raccoon", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"),
        ]))
        let showSidebar = NSMenuItem(title: "Show Sidebar", action: #selector(NSSplitViewController.toggleSidebar(_:)), keyEquivalent: "s")
        showSidebar.keyEquivalentModifierMask = [.control, .command]
        // The inspector's shortcut is still an open UI question.
        menu.addItem(submenu("View", [
            showSidebar,
            NSMenuItem(title: "Show Inspector", action: #selector(NSSplitViewController.toggleInspector(_:)), keyEquivalent: ""),
        ]))
        let window = submenu("Window", [
            NSMenuItem(title: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m"),
            NSMenuItem(title: "Zoom", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: ""),
        ])
        NSApp?.windowsMenu = window.submenu
        menu.addItem(window)
        return menu
    }

    private static func submenu(_ title: String, _ items: [NSMenuItem]) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.submenu = NSMenu(title: title)
        items.forEach(item.submenu!.addItem)
        return item
    }
}

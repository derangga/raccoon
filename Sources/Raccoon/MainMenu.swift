import AppKit

/// The menu bar. The other menus arrive with the features that need them.
enum MainMenu {
    static func make() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(submenu("Raccoon", [
            NSMenuItem(title: "Hide Raccoon", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h"),
            .separator(),
            NSMenuItem(title: "Quit Raccoon", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"),
        ]))
        // No target: the AppDelegate, which owns the WindowModel, takes the Tab items.
        menu.addItem(submenu("File", [
            NSMenuItem(title: "New Tab", action: #selector(AppDelegate.newTab(_:)), keyEquivalent: "t"),
        ]))
        let copyAsCurl = copyAsCurl()
        copyAsCurl.keyEquivalent = "c"
        copyAsCurl.keyEquivalentModifierMask = [.command, .shift]
        let redo = NSMenuItem(title: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        // No target: each goes to the first responder, which is the field or text view being edited.
        menu.addItem(submenu("Edit", [
            NSMenuItem(title: "Undo", action: Selector(("undo:")), keyEquivalent: "z"),
            redo,
            .separator(),
            NSMenuItem(title: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x"),
            NSMenuItem(title: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c"),
            NSMenuItem(title: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v"),
            NSMenuItem(title: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a"),
            .separator(),
            copyAsCurl,
        ]))
        let showSidebar = NSMenuItem(title: "Show Sidebar", action: #selector(NSSplitViewController.toggleSidebar(_:)), keyEquivalent: "s")
        showSidebar.keyEquivalentModifierMask = [.control, .command]
        // The inspector's shortcut is still an open UI question.
        menu.addItem(submenu("View", [
            showSidebar,
            NSMenuItem(title: "Show Inspector", action: #selector(NSSplitViewController.toggleInspector(_:)), keyEquivalent: ""),
        ]))
        let next = NSMenuItem(title: "Show Next Tab", action: #selector(AppDelegate.showNextTab(_:)), keyEquivalent: "\t")
        next.keyEquivalentModifierMask = .control
        let previous = NSMenuItem(title: "Show Previous Tab", action: #selector(AppDelegate.showPreviousTab(_:)), keyEquivalent: "\t")
        previous.keyEquivalentModifierMask = [.control, .shift]
        // ⌘1…⌘9 work without nine items in the menu.
        let numbered = (1...9).map { number in
            let item = NSMenuItem(title: "Show Tab \(number)", action: #selector(AppDelegate.showTab(_:)), keyEquivalent: "\(number)")
            item.tag = number
            item.isHidden = true
            item.allowsKeyEquivalentWhenHidden = true
            return item
        }
        let window = submenu("Window", [
            NSMenuItem(title: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m"),
            NSMenuItem(title: "Zoom", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: ""),
            .separator(),
            next,
            previous,
        ] + numbered)
        NSApp?.windowsMenu = window.submenu
        menu.addItem(window)
        return menu
    }

    /// No target: the selected Tab's TabViewController takes it.
    static func copyAsCurl() -> NSMenuItem {
        NSMenuItem(title: "Copy as Curl", action: #selector(TabViewController.copyAsCurl(_:)), keyEquivalent: "")
    }

    private static func submenu(_ title: String, _ items: [NSMenuItem]) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.submenu = NSMenu(title: title)
        items.forEach(item.submenu!.addItem)
        return item
    }
}

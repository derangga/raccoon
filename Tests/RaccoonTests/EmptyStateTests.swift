import AppKit
@testable import Raccoon
import Testing

/// The empty state's rows read their shortcut from the menu item, as the menu bar shows it.
@MainActor
struct EmptyStateTests {
    static func item(_ key: String, _ mask: NSEvent.ModifierFlags) -> NSMenuItem {
        let item = NSMenuItem(title: "x", action: #selector(AppDelegate.newTab(_:)), keyEquivalent: key)
        item.keyEquivalentModifierMask = mask
        return item
    }

    @Test(arguments: [
        ("t", NSEvent.ModifierFlags.command.rawValue, ["⌘", "T"]),
        ("i", NSEvent.ModifierFlags([.command, .shift]).rawValue, ["⇧", "⌘", "I"]),
        ("e", NSEvent.ModifierFlags([.control, .option]).rawValue, ["⌃", "⌥", "E"]),
        ("", NSEvent.ModifierFlags.command.rawValue, []),
    ])
    func `a shortcut is its modifiers in menu-bar order, then the key`(key: String, mask: UInt, keys: [String]) {
        #expect(CommandRow.keys(Self.item(key, NSEvent.ModifierFlags(rawValue: mask))) == keys)
    }
}

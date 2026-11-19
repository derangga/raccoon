import AppKit

/// Delete… on an Example, and ⌫ on its row: a native alert sheet (examples.md). Cancel is the
/// default, so Return keeps the Example and no key a hand rests on deletes it. An Example has no
/// file of its own, so the text says there is no Trash.
enum DeleteExampleConfirm {
    static func alert(name: String) -> NSAlert {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Delete the Example “\(name)”?"
        alert.informativeText = "It is removed from its Request's file, not moved to the Trash. This can't be undone."
        // The first button is the default; the one titled Cancel also answers Esc.
        alert.addButton(withTitle: "Cancel")
        alert.addButton(withTitle: "Delete").hasDestructiveAction = true
        return alert
    }

    static func ask(name: String, in window: NSWindow, reply: @escaping (Bool) -> Void) {
        alert(name: name).beginSheetModal(for: window) { reply($0 == .alertSecondButtonReturn) }
    }
}

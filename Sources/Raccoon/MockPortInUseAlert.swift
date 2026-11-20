import AppKit

/// Start Mock Server on a remembered port that is taken: a native alert sheet. Use Another Port is
/// the default and binds a free one; Cancel also answers Esc and starts nothing (mock-server.md).
enum MockPortInUseAlert {
    static func alert(port: UInt16) -> NSAlert {
        let alert = NSAlert()
        alert.messageText = "Port \(port) is in use."
        alert.addButton(withTitle: "Use Another Port")
        alert.addButton(withTitle: "Cancel")
        return alert
    }

    static func ask(port: UInt16, in window: NSWindow, reply: @escaping (Bool) -> Void) {
        alert(port: port).beginSheetModal(for: window) { reply($0 == .alertFirstButtonReturn) }
    }
}

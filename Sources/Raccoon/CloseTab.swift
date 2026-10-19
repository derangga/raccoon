import AppKit
import RaccoonDomain

/// Save joins these when Collections can write a Request; it saves, then closes.
enum CloseChoice {
    case dontSave, cancel
}

/// ⌘W and the ✕: asks first when closing would lose something (tabs.md §close).
final class TabCloser {
    private let window: WindowModel
    private let ask: (TabModel, @escaping (CloseChoice) -> Void) -> Void

    /// `ask` is CloseConfirm's sheet in the app.
    init(window: WindowModel, ask: @escaping (TabModel, @escaping (CloseChoice) -> Void) -> Void) {
        self.window = window
        self.ask = ask
    }

    func close(_ model: TabModel) {
        guard model.tab.hasLosableContent else { return window.close(model.tab.id) }
        ask(model) { [window] choice in
            switch choice {
            case .dontSave: window.close(model.tab.id)
            case .cancel: break
            }
        }
    }
}

/// The close confirmation (design-system.md §6): an NSAlert sheet on the window.
enum CloseConfirm {
    static func alert(for model: TabModel) -> NSAlert {
        let alert = NSAlert()
        alert.messageText = "Close “\(model.tab.title)” without saving?"
        alert.informativeText = model.tab.source == .draft
            ? "This Draft hasn't been saved. Its request will be lost."
            : "Your edits to this Request haven't been saved and will be lost."
        // The first button would answer Return; discarding work never takes a key a hand rests on.
        let dontSave = alert.addButton(withTitle: "Don't Save")
        dontSave.hasDestructiveAction = true
        dontSave.keyEquivalent = "d"
        dontSave.keyEquivalentModifierMask = .command
        alert.addButton(withTitle: "Cancel").keyEquivalent = "\u{1b}"
        return alert
    }

    /// Cancel and Esc give focus back to where it was before the sheet.
    static func ask(_ model: TabModel, in window: NSWindow, reply: @escaping (CloseChoice) -> Void) {
        // A second ⌘W while the sheet is up asks nothing more.
        guard window.attachedSheet == nil else { return }
        let focused = window.firstResponder
        alert(for: model).beginSheetModal(for: window) { response in
            let choice: CloseChoice = response == .alertFirstButtonReturn ? .dontSave : .cancel
            if choice == .cancel, let focused { window.makeFirstResponder(focused) }
            reply(choice)
        }
    }
}

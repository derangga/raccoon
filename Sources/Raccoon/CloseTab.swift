import AppKit
import RaccoonDomain

enum CloseChoice {
    case save, dontSave, cancel
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
            // ponytail: Save is disabled in the alert; the Collections epic saves here, then closes.
            case .save: break
            }
        }
    }
}

/// The close confirmation (design-system.md §6): an NSAlert sheet on the window.
enum CloseConfirm {
    static func alert(for model: TabModel) -> NSAlert {
        let alert = NSAlert()
        alert.messageText = "Do you want to save the changes to “\(model.tab.title)”?"
        alert.informativeText = "Your changes will be lost if you don't save them."
        alert.addButton(withTitle: "Save").isEnabled = false
        let dontSave = alert.addButton(withTitle: "Don't Save")
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
            let choice: CloseChoice = switch response {
            case .alertFirstButtonReturn: .save
            case .alertSecondButtonReturn: .dontSave
            default: .cancel
            }
            if choice == .cancel, let focused { window.makeFirstResponder(focused) }
            reply(choice)
        }
    }
}

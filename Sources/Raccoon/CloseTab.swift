import AppKit
import RaccoonDomain

/// Save saves, then closes once the write landed.
enum CloseChoice {
    case save, dontSave, cancel
}

/// ⌘W and the ✕: asks first when closing would lose something (tabs.md §close).
final class TabCloser {
    private let window: WindowModel
    private let saver: DraftSaver
    private let ask: (TabModel, @escaping (CloseChoice) -> Void) -> Void

    /// `ask` is CloseConfirm's sheet in the app; `saver` is ⌘S's, sheet and all.
    init(window: WindowModel, saver: DraftSaver, ask: @escaping (TabModel, @escaping (CloseChoice) -> Void) -> Void) {
        self.window = window
        self.saver = saver
        self.ask = ask
    }

    func close(_ model: TabModel) {
        guard model.tab.hasLosableContent else { return window.close(model.tab.id) }
        ask(model) { [window, saver] choice in
            switch choice {
            case .save: saver.save(model) { saved in if saved { window.close(model.tab.id) } }
            case .dontSave: window.close(model.tab.id)
            case .cancel: break
            }
        }
    }
}

/// The close confirmation (design-system.md §6): an NSAlert sheet on the window.
enum CloseConfirm {
    /// `name` is the window's name for the Tab: a Request's own name, a Draft's URL path.
    static func alert(for model: TabModel, name: String) -> NSAlert {
        let alert = NSAlert()
        alert.messageText = "Save “\(name)” before closing?"
        alert.informativeText = model.tab.source == .draft
            ? "This Draft hasn't been saved. Its request will be lost."
            : "Your edits to this Request haven't been saved and will be lost."
        // Return saves: discarding work never takes a key a hand rests on.
        alert.addButton(withTitle: "Save").keyEquivalent = "\r"
        let dontSave = alert.addButton(withTitle: "Don't Save")
        dontSave.hasDestructiveAction = true
        dontSave.keyEquivalent = "d"
        dontSave.keyEquivalentModifierMask = .command
        alert.addButton(withTitle: "Cancel").keyEquivalent = "\u{1b}"
        return alert
    }

    /// Cancel and Esc give focus back to where it was before the sheet.
    static func ask(_ model: TabModel, name: String, in window: NSWindow, reply: @escaping (CloseChoice) -> Void) {
        // A second ⌘W while the sheet is up asks nothing more.
        guard window.attachedSheet == nil else { return }
        let focused = window.firstResponder
        alert(for: model, name: name).beginSheetModal(for: window) { response in
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

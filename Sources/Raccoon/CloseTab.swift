import AppKit
import RaccoonDomain

/// Save saves, then closes once the write landed. Only Don't Save carries the checkbox: Save,
/// Cancel, Esc and ✕ forget it.
enum CloseChoice: Equatable {
    case save, dontSave(alwaysDiscard: Bool), cancel
}

/// "Always discard unsaved changes when closing a Tab", kept in UserDefaults (tabs.md §close).
struct CloseMemory {
    /// Read at every close, so a change counts at once.
    var alwaysDiscards: () -> Bool = { false }
    var remember: (Bool) -> Void = { _ in }
}

/// ⌘W and the ✕: asks first when closing would lose something (tabs.md §close).
final class TabCloser {
    private let window: WindowModel
    private let saver: DraftSaver
    private let memory: CloseMemory
    private let ask: (TabModel, @escaping (CloseChoice) -> Void) -> Void

    /// `ask` is CloseConfirm's sheet in the app; `saver` is ⌘S's, sheet and all.
    init(window: WindowModel, saver: DraftSaver, memory: CloseMemory, ask: @escaping (TabModel, @escaping (CloseChoice) -> Void) -> Void) {
        self.window = window
        self.saver = saver
        self.memory = memory
        self.ask = ask
    }

    func close(_ model: TabModel) {
        switch CloseStep(hasLosableContent: model.tab.hasLosableContent, alwaysDiscards: memory.alwaysDiscards()) {
        case .close: return window.close(model.tab.id)
        case .ask: break
        }
        ask(model) { [window, saver, memory] choice in
            switch choice {
            case .save: saver.save(model) { saved in if saved { window.close(model.tab.id) } }
            case .dontSave(let alwaysDiscard):
                if alwaysDiscard { memory.remember(true) }
                window.close(model.tab.id)
            case .cancel: break
            }
        }
    }
}

/// The close confirmation (design-system.md §6): a card sheet on the window.
final class CloseConfirm: NSViewController {
    let titleLabel = NSTextField(labelWithString: "Save changes?")
    let closeButton = NSButton()
    let body = NSTextField(wrappingLabelWithString: "")
    let alwaysDiscard = NSButton(checkboxWithTitle: "Always discard unsaved changes when closing a Tab", target: nil, action: nil)
    let info = NSImageView()
    let dontSaveButton = NSButton(title: "Don't Save", target: nil, action: nil)
    let cancelButton = NSButton(title: "Cancel", target: nil, action: nil)
    let saveButton = NSButton(title: "Save", target: nil, action: nil)
    private var reply: ((CloseChoice) -> Void)?

    /// `name` is the window's name for the Tab: a Request's own name, a Draft's URL path.
    init(name: String, isDraft: Bool, reply: @escaping (CloseChoice) -> Void) {
        self.reply = reply
        super.init(nibName: nil, bundle: nil)
        title = "Save changes?"
        let rest = isDraft
            ? " hasn't been saved. Save it to a Collection to avoid losing your work."
            : " has unsaved changes. Save these changes to avoid losing your work."
        let text = NSMutableAttributedString(string: name, attributes: [.font: NSFont.systemFont(ofSize: 13, weight: .semibold)])
        text.append(NSAttributedString(string: rest, attributes: [.font: NSFont.systemFont(ofSize: 13)]))
        text.addAttribute(.foregroundColor, value: NSColor.labelColor, range: NSRange(location: 0, length: text.length))
        body.attributedStringValue = text
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// Cancel, Esc and ✕ give focus back to where it was before the sheet.
    static func ask(_ model: TabModel, name: String, in window: NSWindow, reply: @escaping (CloseChoice) -> Void) {
        // A second ⌘W while the sheet is up asks nothing more.
        guard window.attachedSheet == nil else { return }
        let focused = window.firstResponder
        let sheet = CloseConfirm(name: name, isDraft: model.tab.source == .draft) { choice in
            if choice == .cancel, let focused { window.makeFirstResponder(focused) }
            reply(choice)
        }
        window.beginSheet(sheetPanel(sheet, focus: sheet.saveButton))
    }

    override func loadView() {
        titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        closeButton.image = NSImage(systemSymbolName: "xmark", accessibilityDescription: "Cancel")?
            .withSymbolConfiguration(.init(pointSize: 11, weight: .medium))
        closeButton.isBordered = false
        closeButton.contentTintColor = .secondaryLabelColor
        closeButton.toolTip = "Cancel"
        closeButton.setAccessibilityLabel("Cancel")
        body.preferredMaxLayoutWidth = 400
        info.image = NSImage(systemSymbolName: "info.circle", accessibilityDescription: "About this option")?
            .withSymbolConfiguration(.init(pointSize: 12, weight: .regular))
        info.contentTintColor = .secondaryLabelColor
        info.toolTip = "Closing a Tab with unsaved changes will not ask first. Quitting still keeps your Session."

        // Return saves: discarding work never takes a key a hand rests on.
        saveButton.keyEquivalent = "\r"
        cancelButton.keyEquivalent = "\u{1b}"
        dontSaveButton.hasDestructiveAction = true
        dontSaveButton.keyEquivalent = "d"
        dontSaveButton.keyEquivalentModifierMask = .command
        for (button, action) in [(closeButton, #selector(cancel)), (cancelButton, #selector(cancel)),
                                 (dontSaveButton, #selector(dontSave)), (saveButton, #selector(save))] {
            button.target = self
            button.action = action
        }

        let checkRow = NSStackView(views: [alwaysDiscard, info])
        checkRow.spacing = 4
        let buttons = NSStackView()
        buttons.spacing = 8
        buttons.addView(dontSaveButton, in: .leading)
        buttons.addView(cancelButton, in: .trailing)
        buttons.addView(saveButton, in: .trailing)
        let column = NSStackView(views: [titleLabel, body, checkRow, buttons])
        column.orientation = .vertical
        column.alignment = .leading
        column.spacing = 12
        column.setCustomSpacing(16, after: body)
        column.setCustomSpacing(20, after: checkRow)

        let view = NSView()
        for child in [column, closeButton] {
            child.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(child)
        }
        NSLayoutConstraint.activate([
            view.widthAnchor.constraint(equalToConstant: 440),
            column.topAnchor.constraint(equalTo: view.topAnchor, constant: 16),
            column.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            column.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            column.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -16),
            buttons.widthAnchor.constraint(equalTo: column.widthAnchor),
            body.widthAnchor.constraint(equalTo: column.widthAnchor),
            closeButton.widthAnchor.constraint(equalToConstant: 20),
            closeButton.heightAnchor.constraint(equalToConstant: 20),
            closeButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -14),
            closeButton.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
        ])
        self.view = view
    }

    @objc private func save() { finish(.save) }
    @objc private func dontSave() { finish(.dontSave(alwaysDiscard: alwaysDiscard.state == .on)) }
    @objc private func cancel() { finish(.cancel) }

    private func finish(_ choice: CloseChoice) {
        if let panel = view.window, let parent = panel.sheetParent { parent.endSheet(panel) }
        reply?(choice)
        reply = nil
    }
}

import AppKit
import RaccoonDomain

/// What the Leave sheet answers.
enum LeaveChoice: Equatable {
    case saveAll, dontSave, cancel
}

/// Switching Workspace with Tabs that would be lost (workspaces.md §switchWorkspace): asks once for
/// all of them. Save All saves in strip order and stops at the first Tab that does not land.
final class LeaveConfirmer {
    private let saver: DraftSaver
    private let ask: (_ count: Int, _ reply: @escaping (LeaveChoice) -> Void) -> Void

    /// `ask` is LeaveConfirm's sheet in the app; `saver` is ⌘S's, Save Request sheet and all.
    init(saver: DraftSaver, ask: @escaping (Int, @escaping (LeaveChoice) -> Void) -> Void) {
        self.saver = saver
        self.ask = ask
    }

    /// True lets the switch go on: after Don't Save, or when every Tab saved.
    func confirm(_ losing: [TabModel]) async -> Bool {
        let choice = await withCheckedContinuation { continuation in
            ask(losing.count) { continuation.resume(returning: $0) }
        }
        switch choice {
        case .cancel: return false
        case .dontSave: return true
        case .saveAll:
            for model in losing {
                let saved = await withCheckedContinuation { continuation in
                    saver.save(model) { continuation.resume(returning: $0) }
                }
                if !saved { return false }
            }
            return true
        }
    }
}

extension NSWindow {
    /// The sheet a new sheet must hang from: the Workspaces sheet's Remove can ask, and a sheet
    /// attached to the window under it would wait until that one closed.
    var topSheet: NSWindow { attachedSheet?.topSheet ?? self }
}

/// The Leave confirmation (design-system.md §6): a card sheet like CloseConfirm, system colors, no
/// checkbox. Return saves: no key a hand rests on discards work.
final class LeaveConfirm: NSViewController {
    let titleLabel = NSTextField(labelWithString: "Save changes?")
    let body = NSTextField(wrappingLabelWithString: "")
    let dontSaveButton = NSButton(title: "Don't Save", target: nil, action: nil)
    let cancelButton = NSButton(title: "Cancel", target: nil, action: nil)
    let saveButton: NSButton
    private var reply: ((LeaveChoice) -> Void)?

    /// `count` is Tabs with something to lose.
    init(count: Int, reply: @escaping (LeaveChoice) -> Void) {
        self.reply = reply
        saveButton = NSButton(title: Self.saveTitle(count: count), target: nil, action: nil)
        super.init(nibName: nil, bundle: nil)
        title = "Save changes?"
        body.stringValue = Self.message(count: count)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    static func message(count: Int) -> String {
        count == 1
            ? "1 Tab has unsaved changes. Save it before switching Workspaces, or it will be lost."
            : "\(count) Tabs have unsaved changes. Save them before switching Workspaces, or they will be lost."
    }

    static func saveTitle(count: Int) -> String { count == 1 ? "Save" : "Save All" }

    /// Hangs from the window's top sheet. Cancel and Esc give focus back to where it was.
    static func ask(count: Int, in window: NSWindow, reply: @escaping (LeaveChoice) -> Void) {
        let host = window.topSheet
        let focused = host.firstResponder
        let sheet = LeaveConfirm(count: count) { choice in
            if choice == .cancel, let focused { host.makeFirstResponder(focused) }
            reply(choice)
        }
        host.beginSheet(sheetPanel(sheet, focus: sheet.saveButton))
    }

    override func loadView() {
        titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        body.font = .systemFont(ofSize: 13)
        body.textColor = .labelColor
        body.preferredMaxLayoutWidth = 400
        saveButton.keyEquivalent = "\r"
        cancelButton.keyEquivalent = "\u{1b}"
        dontSaveButton.hasDestructiveAction = true
        dontSaveButton.keyEquivalent = "d"
        dontSaveButton.keyEquivalentModifierMask = .command
        for (button, action) in [(cancelButton, #selector(cancel)), (dontSaveButton, #selector(dontSave)), (saveButton, #selector(saveAll))] {
            button.target = self
            button.action = action
        }
        let buttons = NSStackView()
        buttons.spacing = 8
        buttons.addView(dontSaveButton, in: .leading)
        buttons.addView(cancelButton, in: .trailing)
        buttons.addView(saveButton, in: .trailing)
        let column = NSStackView(views: [titleLabel, body, buttons])
        column.orientation = .vertical
        column.alignment = .leading
        column.spacing = 12
        column.setCustomSpacing(20, after: body)
        column.translatesAutoresizingMaskIntoConstraints = false

        let view = NSView()
        view.addSubview(column)
        NSLayoutConstraint.activate([
            view.widthAnchor.constraint(equalToConstant: 440),
            column.topAnchor.constraint(equalTo: view.topAnchor, constant: 16),
            column.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            column.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            column.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -16),
            buttons.widthAnchor.constraint(equalTo: column.widthAnchor),
            body.widthAnchor.constraint(equalTo: column.widthAnchor),
        ])
        self.view = view
    }

    @objc private func saveAll() { finish(.saveAll) }
    @objc private func dontSave() { finish(.dontSave) }
    @objc private func cancel() { finish(.cancel) }

    private func finish(_ choice: LeaveChoice) {
        if let panel = view.window, let parent = panel.sheetParent { parent.endSheet(panel) }
        reply?(choice)
        reply = nil
    }
}

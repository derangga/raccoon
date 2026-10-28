import AppKit
import RaccoonDomain

/// Save saves, then closes once the write landed. Only Don't Save carries the checkbox: Save,
/// Cancel and Esc forget it.
enum CloseChoice: Equatable {
    case save, dontSave(alwaysDiscard: Bool), cancel
}

/// "Always discard unsaved changes when closing a Tab", kept in UserDefaults (tabs.md §close).
struct CloseMemory {
    /// Read at every close, so a change counts at once.
    var alwaysDiscards: () -> Bool = { false }
    var remember: (Bool) -> Void = { _ in }
}

/// Which Tabs a close from the Tab's menu reaches, counted from the Tab it was chosen on.
enum CloseScope { case tab, others, all }

/// ⌘W, the ✕ and the Tab's context menu: asks first when closing would lose something (tabs.md §close).
final class TabCloser {
    private let window: WindowModel
    private let saver: DraftSaver
    private let memory: CloseMemory
    private let confirmForce: (Int, @escaping (Bool) -> Void) -> Void
    private let ask: (TabModel, @escaping (CloseChoice) -> Void) -> Void

    /// `ask` is CloseConfirm's sheet in the app, `confirmForce` is ForceCloseConfirm's, given how many
    /// Tabs would lose something; `saver` is ⌘S's, sheet and all.
    init(window: WindowModel, saver: DraftSaver, memory: CloseMemory, confirmForce: @escaping (Int, @escaping (Bool) -> Void) -> Void,
         ask: @escaping (TabModel, @escaping (CloseChoice) -> Void) -> Void) {
        self.window = window
        self.saver = saver
        self.memory = memory
        self.confirmForce = confirmForce
        self.ask = ask
    }

    /// `done` says whether the Tab closed: false after Cancel, or a Save that did not land.
    func close(_ model: TabModel, then done: @escaping (Bool) -> Void = { _ in }) {
        switch CloseStep(hasLosableContent: model.tab.hasLosableContent, alwaysDiscards: memory.alwaysDiscards()) {
        case .close:
            window.close(model.tab.id)
            return done(true)
        case .ask: break
        }
        ask(model) { [window, saver, memory] choice in
            switch choice {
            case .save:
                saver.save(model) { saved in
                    if saved { window.close(model.tab.id) }
                    done(saved)
                }
            case .dontSave(let alwaysDiscard):
                if alwaysDiscard { memory.remember(true) }
                window.close(model.tab.id)
                done(true)
            case .cancel: done(false)
            }
        }
    }

    /// Close Tab, Close Other Tabs, Close All Tabs and their Force forms. Force discards with no
    /// Close sheet. Force Close All Tabs first asks once when some Tab would lose something, unless
    /// the user always discards; Force Close Tab is the quick path and never asks. Otherwise the
    /// Tabs go one at a time in strip order, and a Cancel or a Save that did not land stops there:
    /// the rest stay open.
    func close(_ scope: CloseScope, of model: TabModel, force: Bool = false) {
        let models = switch scope {
        case .tab: [model]
        case .others: window.tabs.filter { $0 !== model }
        case .all: window.tabs
        }
        if force {
            let losing = models.filter { $0.tab.hasLosableContent }.count
            if scope == .all, losing > 0, !memory.alwaysDiscards() {
                confirmForce(losing) { [self] confirmed in if confirmed { discard(models) } }
            } else {
                discard(models)
            }
        } else {
            closeInOrder(models[...])
        }
    }

    private func discard(_ models: [TabModel]) {
        for model in models { window.close(model.tab.id) }
    }

    private func closeInOrder(_ models: ArraySlice<TabModel>) {
        guard let first = models.first else { return }
        close(first) { [self] closed in if closed { closeInOrder(models.dropFirst()) } }
    }
}

/// The close confirmation (design-system.md §6): a card sheet on the window.
final class CloseConfirm: NSViewController {
    let titleLabel = NSTextField(labelWithString: "Save changes?")
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

    /// Cancel and Esc give focus back to where it was before the sheet.
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
        for (button, action) in [(cancelButton, #selector(cancel)), (dontSaveButton, #selector(dontSave)), (saveButton, #selector(save))] {
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
        column.translatesAutoresizingMaskIntoConstraints = false
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

    @objc private func save() { finish(.save) }
    @objc private func dontSave() { finish(.dontSave(alwaysDiscard: alwaysDiscard.state == .on)) }
    @objc private func cancel() { finish(.cancel) }

    private func finish(_ choice: CloseChoice) {
        if let panel = view.window, let parent = panel.sheetParent { parent.endSheet(panel) }
        reply?(choice)
        reply = nil
    }
}

/// The Force Close All Tabs confirmation: a card sheet like CloseConfirm, system colors, no
/// checkbox. Return confirms nothing: Esc cancels and Force Close is only ever clicked.
final class ForceCloseConfirm: NSViewController {
    let titleLabel = NSTextField(labelWithString: "Confirm force close")
    let body = NSTextField(wrappingLabelWithString: "")
    let cancelButton = NSButton(title: "Cancel", target: nil, action: nil)
    let forceButton = NSButton(title: "Force Close", target: nil, action: nil)
    private var reply: ((Bool) -> Void)?

    /// `losing` is how many Tabs have something to lose.
    init(losing: Int, reply: @escaping (Bool) -> Void) {
        self.reply = reply
        super.init(nibName: nil, bundle: nil)
        title = "Confirm force close"
        body.stringValue = Self.message(count: losing)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    static func message(count: Int) -> String {
        let tabs = count == 1 ? "1 Tab has" : "\(count) Tabs have"
        let these = count == 1 ? "it" : "these Tabs"
        return "\(tabs) unsaved changes. Your changes will be lost if you force close \(these). Are you sure you want to force close?"
    }

    /// Cancel and Esc give focus back to where it was before the sheet.
    static func ask(losing: Int, in window: NSWindow, reply: @escaping (Bool) -> Void) {
        guard window.attachedSheet == nil else { return }
        let focused = window.firstResponder
        let sheet = ForceCloseConfirm(losing: losing) { confirmed in
            if !confirmed, let focused { window.makeFirstResponder(focused) }
            reply(confirmed)
        }
        window.beginSheet(sheetPanel(sheet, focus: sheet.cancelButton))
    }

    override func loadView() {
        titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        body.font = .systemFont(ofSize: 13)
        body.textColor = .labelColor
        body.preferredMaxLayoutWidth = 400
        cancelButton.keyEquivalent = "\u{1b}"
        // Red, filled, whatever the window's state: the system's destructive tint shows only on a
        // default button, and Return must not be this one.
        forceButton.hasDestructiveAction = true
        forceButton.isBordered = false
        forceButton.wantsLayer = true
        forceButton.layer?.backgroundColor = NSColor.systemRed.cgColor
        forceButton.layer?.cornerRadius = 6
        forceButton.attributedTitle = NSAttributedString(string: forceButton.title, attributes: [.foregroundColor: NSColor.white, .font: NSFont.systemFont(ofSize: 13)])
        for (button, action) in [(cancelButton, #selector(cancel)), (forceButton, #selector(force))] {
            button.target = self
            button.action = action
        }
        let buttons = NSStackView()
        buttons.spacing = 8
        buttons.addView(cancelButton, in: .trailing)
        buttons.addView(forceButton, in: .trailing)
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
            forceButton.heightAnchor.constraint(equalTo: cancelButton.heightAnchor),
            forceButton.widthAnchor.constraint(equalToConstant: forceButton.intrinsicContentSize.width + 28),
        ])
        self.view = view
    }

    @objc private func cancel() { finish(false) }
    @objc private func force() { finish(true) }

    private func finish(_ confirmed: Bool) {
        if let panel = view.window, let parent = panel.sheetParent { parent.endSheet(panel) }
        reply?(confirmed)
        reply = nil
    }
}

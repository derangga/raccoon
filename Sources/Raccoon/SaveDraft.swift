import AppKit
import RaccoonDomain

/// What the Save Request sheet answers; nil is Cancel.
struct SaveDraftAnswer: Equatable {
    var name: String
    var location: SaveLocation
}

/// ⌘S: a Request Tab saves at once; a Draft asks where first (collections.md §saveDraft).
final class DraftSaver {
    typealias Ask = (_ locations: [String], _ default: String?, _ reply: @escaping (SaveDraftAnswer?) -> Void) -> Void

    private let window: WindowModel
    private let ask: Ask
    private let focusURL: () -> Void

    /// `ask` is the sheet in the app; `focusURL` gives focus back to the URL field after it.
    init(window: WindowModel, ask: @escaping Ask, focusURL: @escaping () -> Void) {
        self.window = window
        self.ask = ask
        self.focusURL = focusURL
    }

    /// `done` learns whether the write landed: the close prompt closes only then.
    func save(_ model: TabModel, then done: @escaping (Bool) -> Void = { _ in }) {
        guard model.tab.source == .draft else {
            window.save(model.tab.id)
            return done(!model.tab.isDirty && model.notice == nil)
        }
        // The window banner already says why there is nowhere to save.
        guard window.dataFolderError == nil else { return done(false) }
        ask(window.index.folders, window.lastSaveLocation) { [window, focusURL] answer in
            if let answer { window.saveDraft(model.tab.id, name: answer.name, in: answer.location) }
            focusURL()
            done(model.tab.source != .draft)
        }
    }
}

/// The Save Request sheet (design-system §6 Save Draft sheet): Name, and Location as a path.
final class SaveDraftSheet: NSViewController, NSTextFieldDelegate {
    let heading = NSTextField(labelWithString: "Save Request")
    let nameField = NSTextField()
    private(set) var nameLabel: NSTextField!
    let locationPopUp = NSPopUpButton()
    let collectionField = NSTextField()
    private(set) var collectionRow: NSGridRow!
    let cancelButton = NSButton(title: "Cancel", target: nil, action: nil)
    let saveButton = NSButton(title: "Save", target: nil, action: nil)

    private let locations: [String]
    private let defaultLocation: String?
    private var reply: ((SaveDraftAnswer?) -> Void)?

    init(locations: [String], default defaultLocation: String?, reply: @escaping (SaveDraftAnswer?) -> Void) {
        self.locations = locations
        self.defaultLocation = defaultLocation
        self.reply = reply
        super.init(nibName: nil, bundle: nil)
        title = "Save Request"
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// Shown as a sheet on `window`; the Name field has focus.
    static func present(on window: NSWindow, locations: [String], default defaultLocation: String?,
                        reply: @escaping (SaveDraftAnswer?) -> Void) {
        let sheet = SaveDraftSheet(locations: locations, default: defaultLocation, reply: reply)
        window.beginSheet(sheetPanel(sheet, focus: sheet.nameField))
    }

    override func loadView() {
        heading.font = .systemFont(ofSize: 13, weight: .semibold)
        for field in [nameField, collectionField] {
            field.delegate = self
            field.widthAnchor.constraint(equalToConstant: 260).isActive = true
        }
        nameField.setAccessibilityLabel("Name")
        collectionField.setAccessibilityLabel("Collection")
        if locations.isEmpty {
            locationPopUp.addItem(withTitle: "New Collection…")
        } else {
            for location in locations {
                locationPopUp.addItem(withTitle: location.replacingOccurrences(of: "/", with: " ▸ "))
                locationPopUp.lastItem?.representedObject = location
            }
            locationPopUp.selectItem(at: defaultLocation.flatMap(locations.firstIndex(of:)) ?? 0)
        }
        locationPopUp.setAccessibilityLabel("Location")

        let label = { (text: String) in
            let field = NSTextField(labelWithString: text)
            field.alignment = .right
            return field
        }
        nameLabel = label("Name")
        let grid = NSGridView(views: [
            [nameLabel, nameField],
            [label("Location"), locationPopUp],
            [label("Collection"), collectionField],
        ])
        grid.column(at: 0).width = 70
        grid.rowSpacing = 8
        grid.columnSpacing = 10
        grid.rowAlignment = .firstBaseline
        collectionRow = grid.row(at: 2)
        collectionRow.isHidden = !locations.isEmpty

        cancelButton.keyEquivalent = "\u{1b}"
        cancelButton.target = self
        cancelButton.action = #selector(cancel)
        saveButton.keyEquivalent = "\r"
        saveButton.target = self
        saveButton.action = #selector(save)
        view = sheetContent(heading: heading, grid: grid, buttons: [cancelButton, saveButton])
        validate()
    }

    func controlTextDidChange(_ notification: Notification) {
        validate()
    }

    private var answer: SaveDraftAnswer? {
        let name = nameField.stringValue.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return nil }
        if locations.isEmpty {
            let collection = collectionField.stringValue.trimmingCharacters(in: .whitespaces)
            return collection.isEmpty ? nil : SaveDraftAnswer(name: name, location: .newCollection(collection))
        }
        guard let path = locationPopUp.selectedItem?.representedObject as? String else { return nil }
        return SaveDraftAnswer(name: name, location: .folder(path))
    }

    private func validate() {
        saveButton.isEnabled = answer != nil
    }

    @objc private func save() {
        guard let answer else { return }
        finish(answer)
    }

    @objc private func cancel() {
        finish(nil)
    }

    private func finish(_ answer: SaveDraftAnswer?) {
        if let panel = view.window, let parent = panel.sheetParent { parent.endSheet(panel) }
        reply?(answer)
        reply = nil
    }
}

/// The panel a sheet is shown in; `focus` has focus when it opens.
func sheetPanel(_ sheet: NSViewController, focus: NSView) -> NSWindow {
    let panel = NSWindow(contentViewController: sheet)
    panel.initialFirstResponder = focus
    return panel
}

/// A native sheet's body: heading, a label-and-field grid, and buttons on the trailing edge.
/// The 16 pt margins are constraints on a plain view: as a window's content view, an
/// NSStackView let its edge insets break and its grid run to the panel's edges.
func sheetContent(heading: NSView, grid: NSGridView, buttons: [NSButton]) -> NSView {
    grid.column(at: 0).xPlacement = .trailing
    let row = NSStackView()
    row.spacing = 8
    for button in buttons { row.addView(button, in: .trailing) }
    let column = NSStackView(views: [heading, grid, row])
    column.orientation = .vertical
    column.alignment = .leading
    column.spacing = 12
    column.setCustomSpacing(16, after: grid)
    column.translatesAutoresizingMaskIntoConstraints = false
    let view = NSView()
    view.addSubview(column)
    NSLayoutConstraint.activate([
        column.topAnchor.constraint(equalTo: view.topAnchor, constant: 16),
        column.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
        column.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
        column.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -12),
        row.widthAnchor.constraint(equalTo: column.widthAnchor),
    ])
    return view
}

/// One name: New Collection, New Folder and Rename (design-system §6 Name sheet).
final class NameSheet: NSViewController, NSTextFieldDelegate {
    let heading = NSTextField(labelWithString: "")
    let nameField = NSTextField()
    let cancelButton = NSButton(title: "Cancel", target: nil, action: nil)
    let confirmButton = NSButton(title: "", target: nil, action: nil)
    private var reply: ((String?) -> Void)?

    init(title: String, name: String, button: String, reply: @escaping (String?) -> Void) {
        self.reply = reply
        super.init(nibName: nil, bundle: nil)
        self.title = title
        heading.stringValue = title
        nameField.stringValue = name
        confirmButton.title = button
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    static func present(on window: NSWindow, title: String, name: String, button: String, reply: @escaping (String?) -> Void) {
        let sheet = NameSheet(title: title, name: name, button: button, reply: reply)
        window.beginSheet(sheetPanel(sheet, focus: sheet.nameField))
    }

    override func loadView() {
        heading.font = .systemFont(ofSize: 13, weight: .semibold)
        nameField.delegate = self
        nameField.setAccessibilityLabel("Name")
        nameField.widthAnchor.constraint(equalToConstant: 260).isActive = true
        let label = NSTextField(labelWithString: "Name")
        label.alignment = .right
        let grid = NSGridView(views: [[label, nameField]])
        grid.column(at: 0).width = 70
        grid.columnSpacing = 10
        grid.rowAlignment = .firstBaseline
        cancelButton.keyEquivalent = "\u{1b}"
        cancelButton.target = self
        cancelButton.action = #selector(cancel)
        confirmButton.keyEquivalent = "\r"
        confirmButton.target = self
        confirmButton.action = #selector(confirm)
        view = sheetContent(heading: heading, grid: grid, buttons: [cancelButton, confirmButton])
        validate()
    }

    func controlTextDidChange(_ notification: Notification) { validate() }

    private var name: String? {
        let name = nameField.stringValue.trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? nil : name
    }

    private func validate() { confirmButton.isEnabled = name != nil }

    @objc private func confirm() {
        guard let name else { return }
        finish(name)
    }

    @objc private func cancel() { finish(nil) }

    private func finish(_ name: String?) {
        if let panel = view.window, let parent = panel.sheetParent { parent.endSheet(panel) }
        reply?(name)
        reply = nil
    }
}

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

    func save(_ model: TabModel) {
        guard model.tab.source == .draft else { return window.save(model.tab.id) }
        // The window banner already says why there is nowhere to save.
        guard window.dataFolderError == nil else { return }
        ask(window.index.folders, window.lastSaveLocation) { [window, focusURL] answer in
            if let answer { window.saveDraft(model.tab.id, name: answer.name, in: answer.location) }
            focusURL()
        }
    }
}

/// The Save Request sheet (design-system §6 Save Draft sheet): Name, and Location as a path.
final class SaveDraftSheet: NSViewController, NSTextFieldDelegate {
    let heading = NSTextField(labelWithString: "Save Request")
    let nameField = NSTextField()
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
        let panel = NSWindow(contentViewController: sheet)
        panel.initialFirstResponder = sheet.nameField
        window.beginSheet(panel)
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
        let grid = NSGridView(views: [
            [label("Name"), nameField],
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
        let buttons = NSStackView(views: [cancelButton, saveButton])
        buttons.spacing = 8

        let column = NSStackView(views: [heading, grid, buttons])
        column.orientation = .vertical
        column.alignment = .leading
        column.spacing = 12
        column.edgeInsets = NSEdgeInsets(top: 16, left: 16, bottom: 12, right: 16)
        column.setCustomSpacing(16, after: grid)
        buttons.trailingAnchor.constraint(equalTo: column.trailingAnchor, constant: -16).isActive = true
        view = column
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

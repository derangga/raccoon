import AppKit
@testable import Raccoon
import RaccoonData
import RaccoonDomain
import RaccoonTesting
import Testing

/// ⌘S on a Draft, over a live store in a temp dir.
@MainActor
struct SaveDraftTests {
    let temp = FileManager.default.temporaryDirectory.appending(path: "raccoon-\(UUID())")
    var root: URL { temp.appending(path: "Raccoon") }

    func makeWindow() -> WindowModel {
        WindowModel(
            dataFolder: .test(root), folderWatch: ManualFolderWatch(),
            sessionStore: DiskSessionStore(directory: temp.appending(path: "Support"), root: root.path), secrets: InMemorySecretStore(),
            instants: FixedInstantSource(.now),
            makeTab: {
                TabModel(transport: ScriptedTransport(.failure(.timedOut)), secrets: InMemorySecretStore(), files: DictionaryFileReading([:]),
                         instants: FixedInstantSource(.now), clipboard: RecordingClipboardWriter())
            }
        )
    }

    /// A window over a Data Folder holding `folders`, with its one Draft given a URL.
    func window(folders: [String] = ["Payments API/Webhooks"]) throws -> (WindowModel, TabModel) {
        for folder in folders { try FileManager.default.createDirectory(at: root.appending(path: folder), withIntermediateDirectories: true) }
        let window = makeWindow()
        window.loadDataFolder()
        let draft = window.tabs[0]
        draft.typeInURLBar("https://api.example.com/webhooks")
        draft.setMethod("POST")
        return (window, draft)
    }

    @Test func `the Draft becomes the Request it was saved as, and its row appears`() throws {
        let (window, draft) = try window()

        window.saveDraft(draft.tab.id, name: "Create webhook", in: .folder("Payments API/Webhooks"))

        guard case .request(let id) = draft.tab.source else { Issue.record("still a Draft"); return }
        let path = "Payments API/Webhooks/Create webhook.json"
        let written = try Data(contentsOf: root.appending(path: path))
        #expect(try RequestFile.decode(written) == Request(id: id, name: "Create webhook", definition: draft.tab.definition))
        #expect(draft.tab.baseline == draft.tab.definition)
        #expect(!draft.tab.isDirty)
        #expect(window.index.path(of: id) == path)
        #expect(window.name(of: draft.tab) == "Create webhook")
        #expect(window.ledger.isOurs(path, written))
    }

    @Test func `a taken name writes <name> 2.json and keeps the name inside`() throws {
        let (window, draft) = try window(folders: ["Payments API"])
        try RequestFile.encode(Request(id: RequestID(UUID()), name: "Refund", definition: .empty))
            .write(to: root.appending(path: "Payments API/Refund.json"))
        window.loadDataFolder()

        window.saveDraft(draft.tab.id, name: "Refund", in: .folder("Payments API"))

        guard case .request(let id) = draft.tab.source else { Issue.record("still a Draft"); return }
        #expect(window.index.path(of: id) == "Payments API/Refund 2.json")
        #expect(window.name(of: draft.tab) == "Refund")
    }

    @Test func `New Collection… creates the Collection, then the Request in it`() throws {
        let (window, draft) = try window(folders: [])

        window.saveDraft(draft.tab.id, name: "Ping", in: .newCollection("Health"))

        guard case .request(let id) = draft.tab.source else { Issue.record("still a Draft"); return }
        #expect(window.index.path(of: id) == "Health/Ping.json")
        #expect(window.index.collections.map(\.name) == ["Health"])
    }

    @Test func `a write that fails says Not saved and the Tab stays a Draft`() throws {
        let (window, draft) = try window(folders: ["Payments API"])
        let folder = root.appending(path: "Payments API")
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: folder.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: folder.path) }

        window.saveDraft(draft.tab.id, name: "Ping", in: .folder("Payments API"))

        #expect(draft.tab.source == .draft)
        #expect(draft.notice == .notSaved(file: "Ping.json", reason: "permission denied"))
        #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path).isEmpty)
    }

    // MARK: The flow around the sheet

    @Test func `Cancel writes nothing; Save saves and gives focus back to the URL field`() throws {
        let (window, draft) = try window()
        var answers: [SaveDraftAnswer?] = [nil, SaveDraftAnswer(name: "Create webhook", location: .folder("Payments API/Webhooks"))]
        var asked: [(locations: [String], default: String?)] = []
        var focused = 0
        let saver = DraftSaver(window: window, ask: { locations, location, reply in
            asked.append((locations, location))
            reply(answers.removeFirst())
        }, focusURL: { focused += 1 })

        saver.save(draft)
        #expect(draft.tab.source == .draft)
        #expect(try FileManager.default.contentsOfDirectory(atPath: root.appending(path: "Payments API/Webhooks").path).isEmpty)

        saver.save(draft)
        #expect(draft.tab.source != .draft)
        #expect(asked.map(\.locations) == [["Payments API", "Payments API/Webhooks"], ["Payments API", "Payments API/Webhooks"]])
        #expect(focused == 2)
    }

    @Test func `the sheet defaults to the last Location used`() throws {
        let (window, first) = try window()
        window.newTab()
        let second = window.tabs[1]
        second.typeInURLBar("https://api.example.com/x")
        var defaults: [String?] = []
        let saver = DraftSaver(window: window, ask: { _, location, reply in
            defaults.append(location)
            reply(SaveDraftAnswer(name: "R \(defaults.count)", location: .folder("Payments API/Webhooks")))
        }, focusURL: {})

        saver.save(first)
        saver.save(second)

        #expect(defaults == [nil, "Payments API/Webhooks"])
    }

    @Test func `an unwritable Data Folder opens no sheet: the window banner says why`() throws {
        let readOnly = temp.appending(path: "Raccoon")
        try FileManager.default.createDirectory(at: readOnly, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: readOnly.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: readOnly.path) }
        let window = makeWindow()
        window.loadDataFolder()
        var asked = false
        let saver = DraftSaver(window: window, ask: { _, _, _ in asked = true }, focusURL: {})

        saver.save(window.tabs[0])

        #expect(!asked)
        #expect(window.dataFolderError != nil)
    }

    // MARK: The sheet

    @Test func `the sheet reads as board 09: Name, Location as a path, Cancel and Save`() throws {
        var reply: SaveDraftAnswer??
        let sheet = SaveDraftSheet(locations: ["Payments API", "Payments API/Webhooks"], default: "Payments API/Webhooks") { reply = $0 }
        sheet.loadView()

        #expect(sheet.title == "Save Request")
        #expect(sheet.heading.stringValue == "Save Request")
        #expect(sheet.nameField.stringValue == "")
        #expect(sheet.locationPopUp.itemTitles == ["Payments API", "Payments API ▸ Webhooks"])
        #expect(sheet.locationPopUp.titleOfSelectedItem == "Payments API ▸ Webhooks")
        #expect(sheet.collectionRow.isHidden)
        #expect([sheet.cancelButton.title, sheet.saveButton.title] == ["Cancel", "Save"])
        #expect(sheet.saveButton.keyEquivalent == "\r")
        #expect(sheet.cancelButton.keyEquivalent == "\u{1b}")
        #expect(!sheet.saveButton.isEnabled)

        sheet.nameField.stringValue = "  "
        sheet.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: sheet.nameField))
        #expect(!sheet.saveButton.isEnabled)
        sheet.nameField.stringValue = "Create webhook"
        sheet.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: sheet.nameField))
        #expect(sheet.saveButton.isEnabled)

        sheet.saveButton.performClick(nil)
        #expect(reply == SaveDraftAnswer(name: "Create webhook", location: .folder("Payments API/Webhooks")))
    }

    @Test func `with no Collections the Location is New Collection… and asks for its name`() throws {
        var reply: SaveDraftAnswer??
        let sheet = SaveDraftSheet(locations: [], default: nil) { reply = $0 }
        sheet.loadView()

        #expect(sheet.locationPopUp.itemTitles == ["New Collection…"])
        #expect(!sheet.collectionRow.isHidden)
        sheet.nameField.stringValue = "Ping"
        sheet.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: sheet.nameField))
        #expect(!sheet.saveButton.isEnabled)
        sheet.collectionField.stringValue = "Health"
        sheet.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: sheet.collectionField))
        #expect(sheet.saveButton.isEnabled)

        sheet.cancelButton.performClick(nil)
        #expect(reply == .some(nil))
    }
}

/// The sheets laid out in their panel: 16 pt margins, labels right-aligned, buttons trailing.
@MainActor
struct SheetLayoutTests {
    func frame(_ view: NSView, in panel: NSWindow) -> NSRect {
        view.convert(view.bounds, to: panel.contentView)
    }

    @Test func `the Save Request sheet keeps its margins and puts Cancel · Save on the right`() {
        for locations in [["Payments API"], []] {
            let sheet = SaveDraftSheet(locations: locations, default: nil) { _ in }
            let panel = sheetPanel(sheet, focus: sheet.nameField)
            panel.layoutIfNeeded()
            let width = panel.contentView!.bounds.width

            let name = frame(sheet.nameField, in: panel)
            #expect(name.minX >= 16 + 70)
            #expect(name.maxX <= width - 16 + 0.5)
            #expect(abs(frame(sheet.saveButton, in: panel).maxX - (width - 16)) < 1)
            #expect(frame(sheet.cancelButton, in: panel).maxX < frame(sheet.saveButton, in: panel).minX)
            let label = sheet.nameLabel!
            #expect(abs(frame(label, in: panel).maxX - (name.minX - 10)) <= 2)  // a label frame includes its 2 pt inset
        }
    }

    @Test func `the Name sheet keeps its margins and puts its buttons on the right`() {
        let sheet = NameSheet(title: "Rename", name: "Refunds", button: "Rename") { _ in }
        let panel = sheetPanel(sheet, focus: sheet.nameField)
        panel.layoutIfNeeded()
        let width = panel.contentView!.bounds.width

        let name = frame(sheet.nameField, in: panel)
        #expect(name.minX >= 16 + 70)
        #expect(name.maxX <= width - 16 + 0.5)
        #expect(abs(frame(sheet.confirmButton, in: panel).maxX - (width - 16)) < 1)
    }
}

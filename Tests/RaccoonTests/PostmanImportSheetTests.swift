import AppKit
@testable import Raccoon
import RaccoonData
import RaccoonDomain
import RaccoonTesting
import Testing

/// The Postman Import sheet over a window loaded from a temp Data Folder (board 12): the rows,
/// the notes, the footer and the result, from picked files read in memory.
@MainActor
struct PostmanImportSheetTests {
    let temp = FileManager.default.temporaryDirectory.appending(path: "raccoon-\(UUID())")
    var root: URL { temp.appending(path: "Raccoon") }
    let secrets = FlakySecretStore()

    func makeWindow() -> WindowModel {
        let window = WindowModel(
            dataFolder: .test(root), folderWatch: ManualFolderWatch(),
            sessionStore: DiskSessionStore(directory: temp.appending(path: "Support"), root: root.path),
            secrets: secrets, instants: FixedInstantSource(.now),
            makeTab: { [secrets] in
                TabModel(transport: ScriptedTransport(.failure(.timedOut)), secrets: secrets, files: DictionaryFileReading([:]),
                         instants: FixedInstantSource(.now), clipboard: RecordingClipboardWriter())
            }
        )
        window.loadDataFolder()
        return window
    }

    func put(_ data: Data, at path: String) throws {
        let url = root.appending(path: path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url)
    }

    func variable(_ name: String, _ value: String = "v", secret: Bool = false) -> PostmanVariable {
        PostmanVariable(key: name, value: value, type: secret ? "secret" : nil)
    }

    func entry(_ name: String) -> VariableEntry { VariableEntry(name: VariableName(name)!, value: .plain("raccoon")) }

    /// A Workspace with Prod and globals base_url, as on board 12.
    func boardWindow() throws -> WindowModel {
        try put(EnvironmentFile.encode([]), at: "environments/Prod.json")
        try put(EnvironmentFile.encode([entry("base_url")]), at: "globals.json")
        return makeWindow()
    }

    func request(_ name: String, auth: PostmanAuth? = nil) -> PostmanItem {
        .request(PostmanRequest(name: name, url: PostmanURL(raw: "https://api.example/\(name)"), auth: auth))
    }

    var payments: PickedFile {
        PickedFile(name: "Payments API.postman_collection.json", content: .read(.collection(PostmanCollection(
            name: "Payments API",
            items: [.folder(PostmanFolder(name: "Refunds", items: [request("Create refund"), request("List refunds")])), request("Capture charge")]
        ))))
    }

    func environment(_ name: String, _ values: [PostmanVariable]) -> PickedFile {
        PickedFile(name: "\(name).postman_environment.json", content: .read(.environment(PostmanEnvironment(name: name, values: values))))
    }

    var globalsFile: PickedFile {
        PickedFile(name: "workspace.postman_globals.json", content: .read(.globals(
            ["base_url", "a", "b", "c", "d"].map { variable($0) }
        )))
    }

    let insomnia = PickedFile(name: "insomnia-export.json", content: .read(.notPostman))

    // MARK: Reading the picked files

    @Test func `a picked file is read and recognised, and one that can't be read keeps the reason`() {
        let files = DictionaryFileReading([
            "/in/Dev.postman_environment.json": Data(#"{"name":"Dev","values":[],"_postman_variable_scope":"environment"}"#.utf8),
            "/in/notes.json": Data("not json".utf8),
        ])

        let picked = PickedFile.read(["/in/Dev.postman_environment.json", "/in/notes.json", "/in/gone.json"], from: files)

        #expect(picked == [
            PickedFile(name: "Dev.postman_environment.json", content: .read(.environment(PostmanEnvironment(name: "Dev", values: [])))),
            PickedFile(name: "notes.json", content: .read(.notPostman)),
            PickedFile(name: "gone.json", content: .unreadable("No such file")),
        ])
    }

    // MARK: Rows

    @Test func `board 12: one row per file, a taken name renamed, Globals counted, a non-Postman file disabled`() throws {
        let window = try boardWindow()
        let model = PostmanImport(files: [
            payments,
            environment("Dev", [variable("host"), variable("token", secret: true), variable("key", secret: true)]),
            environment("Prod", [variable("host")]),
            globalsFile,
            insomnia,
        ], window: window)

        #expect(model.rows == [
            .init(kind: .collection, title: "Payments API", detail: "Collection · 3 Requests in 1 Folder",
                  source: "Payments API.postman_collection.json", isEnabled: true, isTicked: true),
            .init(kind: .environment, title: "Dev", detail: "Environment · 3 Variables, 2 secrets",
                  source: "Dev.postman_environment.json", isEnabled: true, isTicked: true),
            .init(kind: .environment, title: "Prod → Prod 2", detail: "Environment · 1 Variable · “Prod” already exists",
                  source: "Prod.postman_environment.json", isEnabled: true, isTicked: true),
            .init(kind: .globals, title: "Globals", detail: "4 new · 1 kept as it is in Raccoon (base_url)",
                  source: "workspace.postman_globals.json", isEnabled: true, isTicked: true),
            .init(kind: .other, title: "insomnia-export.json", detail: "Not a Postman export Raccoon reads",
                  source: "", isEnabled: false, isTicked: false),
        ])
    }

    @Test func `a file that can't be read is a disabled row with the reason`() throws {
        let model = PostmanImport(files: [PickedFile(name: "locked.json", content: .unreadable("permission denied"))], window: makeWindow())

        #expect(model.rows == [.init(kind: .other, title: "locked.json", detail: "Can't be read: permission denied", source: "", isEnabled: false, isTicked: false)])
    }

    @Test func `two files of one name: the second is renamed, and unticking the first gives the second its name back`() throws {
        var model = PostmanImport(files: [environment("Stage", []), environment("Stage", [])], window: makeWindow())
        #expect(model.rows.map(\.title) == ["Stage", "Stage → Stage 2"])
        #expect(model.plan.environments.map(\.name) == ["Stage", "Stage 2"])

        model.isTicked[0] = false

        #expect(model.rows.map(\.title) == ["Stage", "Stage"])
        #expect(model.plan.environments.map(\.name) == ["Stage"])
    }

    @Test func `a Collection variable Globals keeps is a note, the Globals file's are on its row`() throws {
        let window = try boardWindow()
        let collection = PickedFile(name: "c.json", content: .read(.collection(PostmanCollection(
            name: "C", items: [], variables: [variable("base_url"), variable("a")]
        ))))
        // Picked first, read after the Collection: "a" is the Collection's, so the file keeps it.
        let model = PostmanImport(files: [globalsFile, collection], window: window)

        #expect(model.rows[0].detail == "3 new · 2 kept as they are in Raccoon (base_url, a)")
        #expect(model.notes.contains(.init(isWarning: false, text: "1 Collection variable is not added: Globals already has it.", names: ["base_url"])))
    }

    @Test func `an empty Collection or Environment name shows the name Import writes`() throws {
        try FileManager.default.createDirectory(at: root.appending(path: "New Collection"), withIntermediateDirectories: true)
        let window = makeWindow()
        let model = PostmanImport(files: [
            PickedFile(name: "c.json", content: .read(.collection(PostmanCollection(name: "", items: [])))),
            environment("", []),
        ], window: window)

        #expect(model.rows.map(\.title) == ["New Collection 2", "New Environment"])
        #expect(window.importName(ofCollection: "") == "New Collection 2")
        #expect(window.importName(ofCollection: "Orders") == "Orders")
    }

    @Test(arguments: [
        ([PostmanItem](), "Collection · No Requests"),
        ([.request(PostmanRequest(name: "a"))], "Collection · 1 Request"),
        ([.folder(PostmanFolder(name: "f", items: [.folder(PostmanFolder(name: "g", items: [.request(PostmanRequest(name: "a"))]))]))],
         "Collection · 1 Request in 2 Folders"),
    ])
    func `a Collection row counts every Request and Folder`(items: [PostmanItem], detail: String) throws {
        let model = PostmanImport(files: [PickedFile(name: "c.json", content: .read(.collection(PostmanCollection(name: "C", items: items))))], window: makeWindow())
        #expect(model.rows[0].detail == detail)
    }

    // MARK: Notes

    @Test func `notes read as board 12, one line each, dynamic variables on one line`() throws {
        let oauth = PostmanAuth(type: "oauth2")
        let collection = PostmanCollection(
            name: "Payments API",
            items: [
                .request(PostmanRequest(name: "Create refund", url: PostmanURL(raw: "https://x/{{$guid}}"), auth: oauth)),
                .request(PostmanRequest(name: "Capture charge", url: PostmanURL(raw: "https://x/{{$timestamp}}"), auth: oauth,
                                        events: [PostmanEvent(listen: "test", exec: "pm.test()")])),
            ],
            auth: PostmanAuth(type: "bearer", parameters: ["token": "t"])
        )
        let model = PostmanImport(files: [PickedFile(name: "p.json", content: .read(.collection(collection)))], window: makeWindow())

        #expect(model.notes == [
            .init(isWarning: true, text: "2 Requests use OAuth 2.0 and are imported with no Auth.", names: ["Create refund", "Capture charge"]),
            .init(isWarning: true, text: "{{$guid}} and {{$timestamp}} in 2 Requests are Postman dynamic variables. They stay undefined, so those Requests won't send until you replace them.",
                  names: ["Create refund", "Capture charge"]),
            .init(isWarning: true, text: "Scripts in 1 Request are not imported. Raccoon runs no pre-request or test scripts.", names: ["Capture charge"]),
        ])
    }

    @Test(arguments: [
        (ImportNote(.authInherited, names: ["a", "b"]), false, "Auth inherited from Folders is copied onto 2 Requests."),
        (ImportNote(.pathVariable, names: ["a"]), false, "Path variables are written into the URL of 1 Request."),
        (ImportNote(.collectionVariables, names: ["C"]), false, "Collection variables of 1 Collection are added to Globals."),
        (ImportNote(.binaryBody, names: ["a"]), true, "1 Request has a binary body and is imported with no body."),
        (ImportNote(.fileOnlyName(path: "a.png"), names: ["a", "b"]), true, "The file “a.png” in 2 Requests has only a name, so they won't send until you pick it again."),
        (ImportNote(.pathVariableEmpty(name: "id"), names: ["a"]), true, ":id has no value in 1 Request, so it stays in the URL as typed."),
        (ImportNote(.examplesDropped, names: ["a", "b"]), true, "Saved examples in 2 Requests are not imported."),
        (ImportNote(.descriptionsDropped, names: ["a"]), true, "1 description is not imported. Raccoon keeps no descriptions."),
        (ImportNote(.itemsSkipped, names: ["a", "b"]), true, "2 Postman items that are neither a Request nor a Folder are skipped."),
        (ImportNote(.variableNameInvalid, names: ["base url"]), true, "1 Variable is not imported: its name can't be used as {{name}}."),
        (ImportNote(.authNotSupported(type: "digest"), names: ["a"]), true, "1 Request uses Digest and is imported with no Auth."),
    ])
    func `each note reads as one sentence`(note: ImportNote, isWarning: Bool, text: String) {
        #expect(PostmanImport.lines([note]) == [.init(isWarning: isWarning, text: text, names: note.names)])
    }

    @Test func `a rename is on its row, not a note, and an empty name is left out of a note's list`() {
        #expect(PostmanImport.lines([ImportNote(.renamed(from: "Prod", to: "Prod 2"), names: ["Prod"])]) == [])
        #expect(PostmanImport.lines([ImportNote(.descriptionsDropped, names: ["", "Refunds"])])
            == [.init(isWarning: true, text: "2 descriptions are not imported. Raccoon keeps no descriptions.", names: ["Refunds"])])
    }

    @Test func `break-ui: 40 Requests fit one line, then and N more`() {
        let names = (1...40).map { "Request number \($0)" }
        // Every character 1 pt wide: 60 pt holds two names and the tail, not three.
        let line = PostmanImport.namesLine(names, width: 60) { CGFloat($0.count) }

        #expect(line == "Request number 1 · Request number 2 and 38 more")
        #expect(PostmanImport.namesLine(["a", "b"], width: 60) { CGFloat($0.count) } == "a · b")
        #expect(PostmanImport.namesLine([String(repeating: "x", count: 90), "b"], width: 60) { CGFloat($0.count) }
            == String(repeating: "x", count: 90) + " and 1 more")
    }

    // MARK: Footer

    @Test func `the footer names the Data Folder, and Import needs a ticked file`() throws {
        var model = PostmanImport(files: [payments, insomnia], window: makeWindow())
        #expect(model.footer == "Imports into \((root.path as NSString).abbreviatingWithTildeInPath). Secrets go to the Keychain.")
        #expect(model.canImport)

        model.isTicked[0] = false

        #expect(!model.canImport)
    }

    @Test func `a Data Folder that can't be written disables Import with the reason`() throws {
        let window = makeWindow()
        try FileManager.default.removeItem(at: root)
        try Data().write(to: root)

        let model = PostmanImport(files: [payments], window: window)

        #expect(model.footer.hasPrefix("Can't import into \((root.path as NSString).abbreviatingWithTildeInPath). "))
        #expect(!model.canImport)
    }

    // MARK: Import and its result

    @Test func `Import writes the ticked files only, and everything landing says to reveal the first Collection`() throws {
        let window = try boardWindow()
        var model = PostmanImport(files: [payments, environment("Prod", []), insomnia], window: window)
        model.isTicked[1] = false

        let outcome = try model.importTicked()

        #expect(outcome.isComplete)
        #expect(outcome.reveal == "Payments API")
        #expect(window.index.collections.map(\.name).contains("Payments API"))
        #expect(!FileManager.default.fileExists(atPath: root.appending(path: "environments/Prod 2.json").path))
    }

    @Test func `a failure and a refused secret are lines on the result, and the landed are named`() throws {
        let window = try boardWindow()
        secrets.refuse(.set, with: .unavailable(-25308))
        let model = PostmanImport(files: [payments, environment("Dev", [variable("api_key", "k", secret: true)])], window: window)
        var outcome = try model.importTicked()
        #expect(outcome.isComplete == false)
        #expect(outcome.landed == "Payments API · Dev")

        // The writer's own sentence for a Collection that did not land.
        outcome = PostmanImport.outcome(
            ImportResult(collections: ["Payments API"], problems: [
                .collectionUnwritable(name: "Orders API", .unwritable(path: "Orders API", reason: "the disk is full")),
                .secretNotStored(name: VariableName("api_key")!, environment: "Dev", .unavailable(-25308)),
            ]),
            planned: ["Payments API", "Orders API", "Dev"]
        )

        #expect(outcome == PostmanImport.Outcome(
            heading: "Imported 2 of 3",
            landed: "Payments API · Dev",
            lines: [
                .init(isFailure: true, text: "Orders API was not written: the disk is full. Nothing of it was left in the Data Folder."),
                .init(isFailure: false, text: "The Keychain refused 1 secret (api_key in Dev). It is imported with no value."),
            ],
            reveal: "Payments API",
            isComplete: false
        ))
    }

    @Test func `Globals that did not write are not landed`() {
        let outcome = PostmanImport.outcome(
            ImportResult(collections: [], problems: [.globalsUnwritable(.unwritable(path: "globals.json", reason: "permission denied"))]),
            planned: ["Globals"]
        )
        #expect(outcome.heading == "Imported 0 of 1")
        #expect(outcome.landed == nil)
        #expect(outcome.lines == [.init(isFailure: true, text: "Globals were not written: permission denied. No Global was added.")])
    }

    // MARK: The sheet

    func sheet(_ model: PostmanImport) -> (PostmanImportSheet, [String?]) {
        var revealed: [String?] = []
        let sheet = PostmanImportSheet(model: model) { revealed.append($0) }
        sheet.view.layoutSubtreeIfNeeded()
        return (sheet, revealed)
    }

    @Test func `Cancel on the sheet writes nothing and reveals nothing`() throws {
        let window = makeWindow()
        var revealed: [String?] = []
        let sheet = PostmanImportSheet(model: PostmanImport(files: [payments], window: window)) { revealed.append($0) }
        sheet.view.layoutSubtreeIfNeeded()

        sheet.cancelButton.performClick(nil)

        #expect(revealed == [])
        #expect(window.index.collections.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: root.appending(path: "Payments API").path))
    }

    @Test func `the sheet is 620 pt wide, shows a row per file, and a problem keeps it open on the result`() throws {
        let window = try boardWindow()
        secrets.refuse(.set, with: .unavailable(-25308))
        var revealed: [String?] = []
        let sheet = PostmanImportSheet(model: PostmanImport(files: [payments, environment("Dev", [variable("k", "v", secret: true)]), insomnia], window: window)) {
            revealed.append($0)
        }
        sheet.view.layoutSubtreeIfNeeded()
        #expect(sheet.view.fittingSize.width == 620)
        #expect(sheet.rowViews.count == 3)
        #expect(sheet.importButton.isEnabled)

        sheet.importButton.performClick(nil)

        #expect(revealed == [])
        #expect(sheet.heading.stringValue == "Imported 2 of 2")
        #expect(sheet.importButton.isHidden)
        sheet.doneButton.performClick(nil)
        #expect(revealed == ["Payments API"])
    }

    @Test func `everything landing closes the sheet at once and reveals the first Collection`() throws {
        var revealed: [String?] = []
        let sheet = PostmanImportSheet(model: PostmanImport(files: [payments], window: makeWindow())) { revealed.append($0) }
        sheet.view.layoutSubtreeIfNeeded()

        sheet.importButton.performClick(nil)

        #expect(revealed == ["Payments API"])
    }
}

@MainActor
struct PostmanImportMenuTests {
    @Test func `File has Import from Postman… on ⇧⌘I, after New Collection, and no other item takes ⇧⌘I`() throws {
        let menu = MainMenu.make(theme: .standalone())
        let file = try #require(menu.item(withTitle: "File")?.submenu)
        let item = try #require(file.item(withTitle: "Import from Postman…"))
        #expect(item.keyEquivalent == "i" && item.keyEquivalentModifierMask == [.command, .shift])
        #expect(item.action == #selector(AppDelegate.importFromPostman(_:)))
        #expect(file.items.map(\.title).prefix(4) == ["New Tab", "New Collection", "", "Import from Postman…"])

        func all(_ menu: NSMenu) -> [NSMenuItem] { menu.items.flatMap { [$0] + ($0.submenu.map(all) ?? []) } }
        let same = all(menu).filter { $0.keyEquivalent.lowercased() == "i" && $0.keyEquivalentModifierMask == [.command, .shift] }
        #expect(same.map(\.title) == ["Import from Postman…"])
    }
}

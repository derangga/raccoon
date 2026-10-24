import Foundation
@testable import Raccoon
import RaccoonData
import RaccoonDomain
import RaccoonTesting
import Testing

/// What the Environments sheet asks of the window: write a set, add, rename and delete an
/// Environment, over a temp Data Folder with an in-memory Keychain.
@MainActor
struct EnvironmentEditingTests {
    let temp = FileManager.default.temporaryDirectory.appending(path: "raccoon-\(UUID())")
    var root: URL { temp.appending(path: "Raccoon") }
    let secrets = InMemorySecretStore()
    let watch = ManualFolderWatch()
    let token = VariableName("token")!

    func makeWindow() -> WindowModel {
        let window = WindowModel(
            dataFolder: .test(root), folderWatch: watch,
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

    func put(_ text: String, at path: String) throws {
        let url = root.appending(path: path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
    }

    func put(_ entries: [VariableEntry], at path: String) throws {
        try put(String(decoding: EnvironmentFile.encode(entries), as: UTF8.self), at: path)
    }

    func entry(_ name: String, _ value: String) -> VariableEntry { VariableEntry(name: VariableName(name)!, value: .plain(value)) }
    func exists(_ path: String) -> Bool { FileManager.default.fileExists(atPath: root.appending(path: path).path) }

    @Test func `writing a set puts its file on disk, the window follows, and the watch echo is ours`() throws {
        try put([entry("host", "dev.example")], at: "environments/Dev.json")
        let window = makeWindow()
        let scans = window.scanCount
        let entries = [entry("host", "dev.example"), entry("tenant", "t1")]

        try window.write(entries, to: "Dev")
        try window.write([entry("path", "/v1")], to: nil)

        let bytes = try Data(contentsOf: root.appending(path: "environments/Dev.json"))
        #expect(bytes == EnvironmentFile.encode(entries))
        #expect(window.environments.first?.entries == entries)
        #expect(window.globals.entries == [entry("path", "/v1")])
        #expect(window.ledger.isOurs("environments/Dev.json", bytes))
        #expect(window.scanCount == scans)
    }

    @Test func `a set that does not decode is kept with its reason, never in the picker, and never written`() throws {
        try put([entry("host", "dev.example")], at: "environments/Dev.json")
        try put("{ not json", at: "environments/Broken.json")
        try put("{ nope", at: "globals.json")
        let window = makeWindow()

        #expect(window.environments.map(\.name) == ["Dev"])
        #expect(window.brokenEnvironments == [BrokenEnvironment(name: "Broken", reason: "Not valid JSON at line 1")])
        #expect(window.globalsProblem == "Not valid JSON at line 1")
        #expect(window.entries(of: "Broken") == nil && window.entries(of: nil) == nil)
        #expect(throws: StoreError.self) { try window.write([], to: "Broken") }
        #expect(throws: StoreError.self) { try window.write([], to: nil) }
        #expect(try String(contentsOf: root.appending(path: "environments/Broken.json"), encoding: .utf8) == "{ not json")
        #expect(try String(contentsOf: root.appending(path: "globals.json"), encoding: .utf8) == "{ nope")
    }

    @Test func `the first Environment makes the environments folder and starts empty`() throws {
        let window = makeWindow()
        #expect(!exists("environments"))

        #expect(try window.newEnvironment() == "New Environment")

        #expect(exists("environments/New Environment.json"))
        #expect(window.environments == [Environment(name: "New Environment", entries: [])])
    }

    @Test func `a new Environment gets 2 and 3 when the name is taken, ignoring case, even by a broken file`() throws {
        try put([], at: "environments/new environment.json")
        try put("{ not json", at: "environments/New Environment 2.json")
        let window = makeWindow()

        #expect(try window.newEnvironment() == "New Environment 3")
        #expect(try window.newEnvironment() == "New Environment 4")
    }

    @Test func `renaming keeps its secrets resolvable, moves the file, and the Active Environment follows`() throws {
        try put([entry("host", "prod.example"), VariableEntry(name: token, value: .secret)], at: "environments/Prod.json")
        try secrets.set("sk_live", environment: "Prod", name: token)
        let window = makeWindow()
        window.pickActiveEnvironment("Prod")
        #expect(window.tabs[0].scope(.read).values[token] == "sk_live")

        try window.renameEnvironment("Prod", to: "Production")

        #expect(window.environments.map(\.name) == ["Production"])
        #expect(window.activeEnvironment == "Production")
        #expect(exists("environments/Production.json") && !exists("environments/Prod.json"))
        #expect(window.tabs[0].scope(.read).values[token] == "sk_live")
        #expect(try secrets.get(environment: "Prod", name: token) == nil)
        #expect(window.ledger.isOurs("environments/Prod.json", nil))
    }

    @Test(arguments: [("Dev", "dev"), ("Dev", "DEV"), ("Dev", " Dev ")])
    func `a name that clashes with another Environment is refused and nothing moves`(taken: String, proposed: String) throws {
        try put([VariableEntry(name: token, value: .secret)], at: "environments/Prod.json")
        try put([], at: "environments/Dev.json")
        try secrets.set("sk", environment: "Prod", name: token)
        let window = makeWindow()

        #expect(throws: EnvironmentEditError.nameTaken(taken)) { try window.renameEnvironment("Prod", to: proposed) }

        #expect(window.environments.map(\.name) == ["Dev", "Prod"])
        #expect(try secrets.get(environment: "Prod", name: token) == "sk")
        #expect(try secrets.get(environment: taken, name: token) == nil)
    }

    @Test func `renaming to its own name, or to nothing, changes nothing; a case change is allowed`() throws {
        try put([], at: "environments/Prod.json")
        let window = makeWindow()

        try window.renameEnvironment("Prod", to: "Prod")
        #expect(throws: EnvironmentEditError.empty) { try window.renameEnvironment("Prod", to: "  ") }
        #expect(window.environments.map(\.name) == ["Prod"])

        try window.renameEnvironment("Prod", to: "prod")
        #expect(window.environments.map(\.name) == ["prod"])
    }

    @Test func `a name with a slash or colon is made safe as a file name`() throws {
        try put([], at: "environments/Prod.json")
        let window = makeWindow()

        try window.renameEnvironment("Prod", to: "EU/Prod: blue")

        #expect(window.environments.map(\.name) == ["EU-Prod- blue"])
    }

    @Test func `deleting an Environment trashes its file, keeps its Keychain items, and clears it when active`() throws {
        try put([VariableEntry(name: token, value: .secret)], at: "environments/Prod.json")
        try secrets.set("sk", environment: "Prod", name: token)
        let window = makeWindow()
        window.pickActiveEnvironment("Prod")

        try window.deleteEnvironment("Prod")

        #expect(window.environments.isEmpty)
        #expect(window.activeEnvironment == nil)
        #expect(try secrets.get(environment: "Prod", name: token) == "sk")
    }

    @Test func `deleting a Variable rewrites the file, then deletes a secret's Keychain item`() throws {
        try put([entry("host", "a"), VariableEntry(name: token, value: .secret)], at: "environments/Prod.json")
        try secrets.set("sk", environment: "Prod", name: token)
        try secrets.set("keep", environment: "Dev", name: token)
        let window = makeWindow()

        try window.removeVariable(at: 1, from: "Prod")
        #expect(window.entries(of: "Prod") == [entry("host", "a")])
        #expect(try secrets.get(environment: "Prod", name: token) == nil)
        #expect(try secrets.get(environment: "Dev", name: token) == "keep")

        try window.removeVariable(at: 0, from: "Prod")
        #expect(window.entries(of: "Prod")?.isEmpty == true)
    }
}

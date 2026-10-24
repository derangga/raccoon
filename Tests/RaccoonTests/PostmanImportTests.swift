import Foundation
@testable import Raccoon
import RaccoonData
import RaccoonDomain
import RaccoonTesting
import Testing

/// Import: an ImportPlan written into a temp Data Folder, with an in-memory Keychain that can be
/// told to refuse.
@MainActor
struct PostmanImportTests {
    let temp = FileManager.default.temporaryDirectory.appending(path: "raccoon-\(UUID())")
    var root: URL { temp.appending(path: "Raccoon") }
    let secrets = FlakySecretStore()
    let watch = ManualFolderWatch()
    let token = VariableName("token")!
    let host = VariableName("host")!
    let ping = Request(id: RequestID(UUID()), name: "Ping", definition: .empty)

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

    func put(_ data: Data, at path: String) throws {
        let url = root.appending(path: path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url)
    }

    func read(_ path: String) throws -> Data { try Data(contentsOf: root.appending(path: path)) }
    func rootNames() throws -> Set<String> { Set(try FileManager.default.contentsOfDirectory(atPath: root.path)) }

    func collection(_ name: String) -> ImportCollection {
        ImportCollection(name: name, nodes: [.request(Request(id: RequestID(UUID()), name: "Ping", definition: .empty))])
    }

    var prod: ImportEnvironment {
        ImportEnvironment(name: "Prod", variables: [
            ImportVariable(name: token, value: .secret("s3cret")),
            ImportVariable(name: host, value: .plain("api.example")),
        ])
    }

    var prodFile: Data {
        EnvironmentFile.encode([VariableEntry(name: token, value: .secret), VariableEntry(name: host, value: .plain("api.example"))])
    }

    @Test func `the plan's files land, and the watch echo of them is ours`() async throws {
        let existing = VariableEntry(name: VariableName("tenant")!, value: .plain("t1"))
        try put(EnvironmentFile.encode([existing]), at: "globals.json")
        let window = makeWindow()
        let scans = window.scanCount
        let apiKey = VariableName("apiKey")!
        let plan = ImportPlan(
            collections: [ImportCollection(name: "Health", nodes: [.request(ping), .folder(name: "Empty", children: [])])],
            environments: [prod],
            globals: [ImportVariable(name: apiKey, value: .secret("k3y")), ImportVariable(name: host, value: .plain("g.example"))],
            notes: []
        )

        let result = try window.importPostman(plan)

        #expect(result == ImportResult(collections: ["Health"], problems: []))
        #expect(try read("Health/Ping.json") == RequestFile.encode(ping))
        #expect(FileManager.default.fileExists(atPath: root.appending(path: "Health/Empty").path))
        #expect(try read("environments/Prod.json") == prodFile)
        #expect(try read("globals.json") == EnvironmentFile.encode([
            existing, VariableEntry(name: apiKey, value: .secret), VariableEntry(name: host, value: .plain("g.example")),
        ]))
        #expect(try secrets.inner.get(environment: "Prod", name: token) == "s3cret")
        #expect(try secrets.inner.get(environment: nil, name: apiKey) == "k3y")
        #expect(window.index.collections.map(\.name) == ["Health"])
        #expect(window.index.path(of: ping.id) == "Health/Ping.json")
        #expect(window.environments.map(\.name) == ["Prod"])

        watch.emit([
            ".raccoon-1", ".raccoon-1/Ping.json", "Health", "Health/Ping.json", "Health/Empty",
            "environments", "environments/Prod.json", "globals.json",
        ])
        for _ in 0..<50 { await Task.yield() }
        #expect(window.scanCount == scans)
    }

    @Test func `a Collection that fails to write leaves nothing, and the others land`() throws {
        let window = makeWindow()
        // Made on disk after the plan, behind the window's back.
        try FileManager.default.createDirectory(at: root.appending(path: "Taken"), withIntermediateDirectories: true)

        let result = try window.importPostman(ImportPlan(
            collections: [collection("A"), collection("Taken"), collection("B")], environments: [], globals: [], notes: []
        ))

        #expect(result.collections == ["A", "B"])
        guard result.problems.count == 1, case .collectionUnwritable("Taken", .unwritable) = result.problems[0] else {
            Issue.record("expected one unwritable Taken, got \(result.problems)")
            return
        }
        #expect(try FileManager.default.contentsOfDirectory(atPath: root.appending(path: "Taken").path).isEmpty)
        #expect(try rootNames() == ["A", "B", "Taken", "raccoon.json"])
    }

    @Test func `a secret the Keychain refuses is written with no value, and noted`() throws {
        let window = makeWindow()
        secrets.refuse(.set, with: .unavailable(-25308))

        let result = try window.importPostman(ImportPlan(collections: [], environments: [prod], globals: [], notes: []))

        #expect(result.problems == [.secretNotStored(name: token, environment: "Prod", .unavailable(-25308))])
        #expect(try read("environments/Prod.json") == prodFile)
        #expect(!String(decoding: try read("environments/Prod.json"), as: UTF8.self).contains("s3cret"))
    }

    @Test func `an Environment file that fails to write takes its secrets back out`() throws {
        try FileManager.default.createDirectory(at: root.appending(path: "environments"), withIntermediateDirectories: true)
        let window = makeWindow()
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: root.appending(path: "environments").path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: root.appending(path: "environments").path) }

        let result = try window.importPostman(ImportPlan(collections: [collection("A")], environments: [prod], globals: [], notes: []))

        #expect(result.collections == ["A"])
        guard result.problems.count == 1, case .environmentUnwritable("Prod", .unwritable) = result.problems[0] else {
            Issue.record("expected one unwritable Prod, got \(result.problems)")
            return
        }
        #expect(try secrets.inner.get(environment: "Prod", name: token) == nil)
    }

    @Test func `an Environment file made on disk since the plan is never written over`() throws {
        let window = makeWindow()
        try put(Data("mine".utf8), at: "environments/prod.json")

        let result = try window.importPostman(ImportPlan(collections: [], environments: [prod], globals: [], notes: []))

        guard result.problems.count == 1, case .environmentUnwritable("Prod", .unwritable) = result.problems[0] else {
            Issue.record("expected one unwritable Prod, got \(result.problems)")
            return
        }
        #expect(try read("environments/prod.json") == Data("mine".utf8))
        #expect(try secrets.inner.get(environment: "Prod", name: token) == nil)
    }

    @Test func `Globals are not added to a globals.json that does not decode`() throws {
        try put(Data("{".utf8), at: "globals.json")
        let window = makeWindow()

        let result = try window.importPostman(ImportPlan(
            collections: [], environments: [], globals: [ImportVariable(name: token, value: .secret("s3cret"))], notes: []
        ))

        guard result.problems.count == 1, case .globalsUnwritable(.unwritable) = result.problems[0] else {
            Issue.record("expected globals unwritable, got \(result.problems)")
            return
        }
        #expect(try read("globals.json") == Data("{".utf8))
        #expect(try secrets.inner.get(environment: nil, name: token) == nil)
    }

    @Test func `empty Collection and Environment names are written as New Collection and New Environment`() throws {
        try FileManager.default.createDirectory(at: root.appending(path: "New Collection"), withIntermediateDirectories: true)
        let window = makeWindow()

        let result = try window.importPostman(ImportPlan(
            collections: [collection("")], environments: [ImportEnvironment(name: "", variables: [])], globals: [], notes: []
        ))

        #expect(result == ImportResult(collections: ["New Collection 2"], problems: []))
        #expect(try read("New Collection 2/Ping.json").isEmpty == false)
        #expect(try read("environments/New Environment.json") == EnvironmentFile.encode([]))
    }

    @Test func `a Data Folder that is not writable refuses Import before writing anything`() throws {
        let window = makeWindow()
        let before = try rootNames()
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: root.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: root.path) }

        #expect {
            try window.importPostman(ImportPlan(collections: [collection("A")], environments: [prod], globals: [], notes: []))
        } throws: { error in
            guard case .unwritable = error as? StoreError else { return false }
            return true
        }
        #expect(throws: StoreError.self) { try window.checkWritable() }
        #expect(try rootNames() == before)
        #expect(try secrets.inner.get(environment: "Prod", name: token) == nil)
    }
}

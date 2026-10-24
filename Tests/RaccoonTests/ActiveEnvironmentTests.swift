import Foundation
@testable import Raccoon
import RaccoonData
import RaccoonDomain
import RaccoonTesting
import Testing

/// Globals and Environments loaded with the Data Folder, and the one Active Environment per window.
@MainActor
struct ActiveEnvironmentTests {
    let temp = FileManager.default.temporaryDirectory.appending(path: "raccoon-\(UUID())")
    var root: URL { temp.appending(path: "Raccoon") }
    var sessions: DiskSessionStore { DiskSessionStore(directory: temp.appending(path: "Support"), root: root.path) }
    let transport = ScriptedTransport(.success(Response(status: 200, headers: [], body: Data(), elapsed: .zero, byteCount: 0)))

    func makeWindow() -> WindowModel {
        WindowModel(
            dataFolder: .test(root), folderWatch: ManualFolderWatch(), sessionStore: sessions,
            secrets: InMemorySecretStore(), instants: FixedInstantSource(.now),
            makeTab: { [transport] in
                TabModel(transport: transport, secrets: InMemorySecretStore(), files: DictionaryFileReading([:]),
                         instants: FixedInstantSource(.now), clipboard: RecordingClipboardWriter())
            }
        )
    }

    func put(_ text: String, at path: String) throws {
        let url = root.appending(path: path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
    }

    func variables(_ pairs: [(String, String)]) -> String {
        String(decoding: EnvironmentFile.encode(pairs.map { VariableEntry(name: VariableName($0.0)!, value: .plain($0.1)) }), as: UTF8.self)
    }

    func putEnvironments() throws {
        try put(variables([("path", "/v1"), ("host", "global.example")]), at: "globals.json")
        try put(variables([("host", "dev.example")]), at: "environments/Dev.json")
        try put(variables([("host", "prod.example")]), at: "environments/Prod.json")
    }

    func sentHosts(_ window: WindowModel) async -> [String?] {
        let before = transport.requests.count
        for model in window.tabs {
            model.send()
            await model.inFlight?.value
        }
        return transport.requests.dropFirst(before).map { $0.url.host() }
    }

    @Test func `Globals and the Environments load with the Data Folder; a broken file is left out`() throws {
        try putEnvironments()
        try put("{ not json", at: "environments/Broken.json")

        let window = makeWindow()
        window.loadDataFolder()

        #expect(window.environments.map(\.name) == ["Dev", "Prod"])
        #expect(window.globals.entries.map(\.name.rawValue) == ["path", "host"])
        #expect(window.activeEnvironment == nil)
        #expect(window.index.collections.isEmpty)
    }

    @Test func `switching the Active Environment changes what every Tab sends`() async throws {
        try putEnvironments()
        let window = makeWindow()
        window.loadDataFolder()
        window.newTab()
        for model in window.tabs { model.typeInURLBar("https://{{host}}{{path}}") }

        #expect(await sentHosts(window) == ["global.example", "global.example"])
        window.pickActiveEnvironment("Prod")
        #expect(await sentHosts(window) == ["prod.example", "prod.example"])
        window.pickActiveEnvironment("Dev")
        #expect(await sentHosts(window) == ["dev.example", "dev.example"])
        window.pickActiveEnvironment(nil)
        #expect(await sentHosts(window) == ["global.example", "global.example"])
    }

    @Test func `the choice is in the Session file once the write runs`() async throws {
        try putEnvironments()
        let window = makeWindow()
        window.loadDataFolder()

        window.pickActiveEnvironment("Prod")
        var stored: String?
        for _ in 0..<100 where stored != "Prod" {
            await Task.yield()
            stored = try sessions.read().map(SessionFile.decode)?.activeEnvironment
        }

        #expect(stored == "Prod")
    }

    @Test(arguments: [("Prod", "Prod"), ("Staging", nil)])
    func `relaunch restores the Active Environment while its file is there, else none`(stored: String, active: String?) throws {
        try putEnvironments()
        try sessions.write(SessionFile.encode(Session(tabs: [], selected: nil, activeEnvironment: stored)))

        let window = makeWindow()
        window.loadDataFolder()

        #expect(window.activeEnvironment == active)
    }
}

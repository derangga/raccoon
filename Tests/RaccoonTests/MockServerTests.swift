import Foundation
@testable import Raccoon
import RaccoonData
import RaccoonDomain
import RaccoonTesting
import Testing

/// startMock, stopMock and the window's hold on a Mock Server, over a live store in a temp dir
/// and a scripted listener: the heads are handed to `answer`, the replies read back.
@MainActor
struct MockServerTests {
    let temp = FileManager.default.temporaryDirectory.appending(path: "raccoon-\(UUID())")
    let watch = ManualFolderWatch()
    var root: URL { temp.appending(path: "Raccoon") }

    static let requestID = RequestID(UUID(uuidString: "00000000-0000-4000-8000-0000000000A1")!)
    static let exampleID = ExampleID(UUID(uuidString: "00000000-0000-4000-8000-0000000000E1")!)
    let path = "Pets/List pets.json"
    static let get = MockRequestHead(method: "GET", path: ["pets"], headers: [], bodyLength: 0)

    static func example(_ body: String, status: Int = 200) -> Example {
        Example(id: exampleID, name: "ok", status: status, body: .text(body))
    }

    func makeWindow(_ listening: any MockListening) -> WindowModel {
        WindowModel(
            dataFolder: .test(root), folderWatch: watch,
            sessionStore: DiskSessionStore(directory: temp.appending(path: "Support"), root: root.path), secrets: InMemorySecretStore(),
            instants: FixedInstantSource(.now), mockListening: listening,
            makeTab: {
                TabModel(transport: ScriptedTransport(.failure(.timedOut(seconds: 60))), secrets: InMemorySecretStore(), files: DictionaryFileReading([:]),
                         instants: FixedInstantSource(.now), clipboard: RecordingClipboardWriter())
            }
        )
    }

    /// A Collection "Pets" holding `GET https://api.example.com/pets` with one Example, and an empty "Other".
    func setUp(_ listening: any MockListening = ScriptedMockListening(), raccoonJSON: String? = nil) throws -> WindowModel {
        let url = root.appending(path: path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.appending(path: "Other"), withIntermediateDirectories: true)
        var definition = RequestDefinition.empty
        definition.method = "GET"
        definition.url = "https://api.example.com/pets"
        try RequestFile.encode(Request(id: Self.requestID, name: "List pets", definition: definition, examples: [Self.example("[1]")])).write(to: url)
        if let raccoonJSON { try Data(raccoonJSON.utf8).write(to: root.appending(path: "raccoon.json")) }
        let window = makeWindow(listening)
        window.loadDataFolder()
        return window
    }

    func raccoonJSON() throws -> (id: WorkspaceID, mocks: [String: MockSettings]) {
        try WorkspaceFile.contents(Data(contentsOf: root.appending(path: "raccoon.json")))
    }

    func body(_ listening: ScriptedMockListening) async -> String? {
        await listening.answer(Self.get).map { String(decoding: $0.body, as: UTF8.self) }
    }

    @Test func `start serves the Collection's Example and shows the server`() async throws {
        let listening = ScriptedMockListening(picked: 50_001)
        let window = try setUp(listening)

        try await window.startMock("Pets")

        #expect(await body(listening) == "[1]")
        let server = try #require(window.mockServers["Pets"])
        #expect(server.port == 50_001)
        #expect(server.url == "http://127.0.0.1:50001")
        #expect(server.allowsCORS)
        #expect(server.routes.count == 1)
    }

    @Test func `starting a running Collection is a no-op`() async throws {
        let listening = ScriptedMockListening()
        let window = try setUp(listening)
        try await window.startMock("Pets")

        try await window.startMock("Pets")

        #expect(listening.requestedPorts == [nil])
    }

    @Test func `a Collection that is not there starts nothing`() async throws {
        let listening = ScriptedMockListening()
        let window = try setUp(listening)

        try await window.startMock("Nope")

        #expect(listening.requestedPorts.isEmpty)
        #expect(window.mockServers.isEmpty)
    }

    @Test func `the remembered port is asked for, and the bound one is written keeping the id and the others`() async throws {
        let id = UUID(uuidString: "00000000-0000-4000-8000-0000000000B1")!
        let existing = WorkspaceFile.encode(WorkspaceID(id), mocks: ["Other": MockSettings(port: 9000, allowsCORS: false), "Pets": MockSettings(port: 8081, allowsCORS: false)])
        let listening = ScriptedMockListening()
        let window = try setUp(listening, raccoonJSON: String(decoding: existing, as: UTF8.self))

        try await window.startMock("Pets")

        #expect(listening.requestedPorts == [8081])
        let written = try raccoonJSON()
        #expect(written.id == WorkspaceID(id))
        #expect(written.mocks == ["Other": MockSettings(port: 9000, allowsCORS: false), "Pets": MockSettings(port: 8081, allowsCORS: false)])
        #expect(window.mockServers["Pets"]?.allowsCORS == false)
    }

    @Test func `a first start picks a port and remembers it with CORS on`() async throws {
        let listening = ScriptedMockListening(picked: 50_002)
        let window = try setUp(listening)

        try await window.startMock("Pets")

        #expect(listening.requestedPorts == [nil])
        #expect(try raccoonJSON().mocks == ["Pets": MockSettings(port: 50_002, allowsCORS: true)])
        // Raccoon's own write: the watch echo is dropped.
        let scans = window.scanCount
        watch.emit(["raccoon.json"])
        for _ in 0..<50 { await Task.yield() }
        #expect(window.scanCount == scans)
    }

    @Test func `Use Another Port asks for no port, and the new one is remembered`() async throws {
        let existing = WorkspaceFile.encode(WorkspaceID(UUID()), mocks: ["Pets": MockSettings(port: 8081, allowsCORS: true)])
        let listening = ScriptedMockListening(picked: 50_003)
        let window = try setUp(listening, raccoonJSON: String(decoding: existing, as: UTF8.self))

        try await window.startMock("Pets", onAnotherPort: true)

        #expect(listening.requestedPorts == [nil])
        #expect(window.mockServers["Pets"]?.port == 50_003)
        #expect(try raccoonJSON().mocks["Pets"]?.port == 50_003)
    }

    @Test(arguments: [MockError.portInUse(8081), .failed("denied")])
    func `a start that fails throws, holds nothing and writes nothing`(error: MockError) async throws {
        let listening = ScriptedMockListening(failing: error)
        let window = try setUp(listening)
        let before = try Data(contentsOf: root.appending(path: "raccoon.json"))

        await #expect(throws: error) { try await window.startMock("Pets") }

        #expect(window.mockServers.isEmpty)
        #expect(try Data(contentsOf: root.appending(path: "raccoon.json")) == before)
    }

    @Test func `an unwritable raccoon json is logged and the server still runs`() async throws {
        let listening = ScriptedMockListening()
        let window = try setUp(listening)
        try FileManager.default.removeItem(at: root.appending(path: "raccoon.json"))

        try await window.startMock("Pets")

        #expect(window.mockServers["Pets"] != nil)
        #expect(await body(listening) == "[1]")
    }

    @Test func `saving an Example changes the next answer`() async throws {
        let listening = ScriptedMockListening()
        let window = try setUp(listening)
        try await window.startMock("Pets")
        #expect(await body(listening) == "[1]")

        try window.updateExample(Self.requestID, Self.example("[2]", status: 201))

        #expect(await body(listening) == "[2]")
        #expect(window.mockServers["Pets"]?.routes.first?.examples.first?.status == 201)
    }

    @Test func `a change on disk is served after the watch batch`() async throws {
        let listening = ScriptedMockListening()
        let window = try setUp(listening)
        try await window.startMock("Pets")
        var definition = RequestDefinition.empty
        definition.method = "GET"
        definition.url = "https://api.example.com/pets"
        try RequestFile.encode(Request(id: Self.requestID, name: "List pets", definition: definition, examples: [Self.example("[3]")]))
            .write(to: root.appending(path: path))

        watch.emit([path])
        for _ in 0..<50 { await Task.yield() }

        #expect(await body(listening) == "[3]")
    }

    @Test func `the CORS toggle reaches the next answer and raccoon json`() async throws {
        let listening = ScriptedMockListening()
        let window = try setUp(listening)
        try await window.startMock("Pets")
        let preflight = MockRequestHead(
            method: "OPTIONS", path: ["pets"],
            headers: [.init(name: "Access-Control-Request-Method", value: "GET")], bodyLength: 0)
        #expect(await listening.answer(preflight)?.status == 204)

        window.setMockAllowsCORS("Pets", false)

        #expect(window.mockServers["Pets"]?.allowsCORS == false)
        #expect(await listening.answer(preflight)?.status != 204)
        #expect(try raccoonJSON().mocks["Pets"]?.allowsCORS == false)
        #expect(try raccoonJSON().mocks["Pets"]?.port == 50_000)
    }

    @Test func `stop closes the listener once and forgets the server`() async throws {
        let listening = ScriptedMockListening()
        let window = try setUp(listening)
        try await window.startMock("Pets")

        window.stopMock("Pets")
        window.stopMock("Pets")

        #expect(listening.stops == 1)
        #expect(window.mockServers.isEmpty)
    }

    @Test func `a Workspace switch stops the server`() async throws {
        let listening = ScriptedMockListening()
        let window = try setUp(listening)
        try await window.startMock("Pets")
        let other = temp.appending(path: "Elsewhere")
        try FileManager.default.createDirectory(at: other, withIntermediateDirectories: true)

        await window.openWorkspace(other.path)

        #expect(listening.stops == 1)
        #expect(window.mockServers.isEmpty)
    }

    @Test func `quit stops every server`() async throws {
        let listening = ScriptedMockListening()
        let window = try setUp(listening)
        try await window.startMock("Pets")

        window.quit()

        #expect(listening.stops == 1)
        #expect(window.mockServers.isEmpty)
    }

    @Test func `renaming the Collection stops its server and keeps no settings for the new name`() async throws {
        let listening = ScriptedMockListening()
        let window = try setUp(listening)
        try await window.startMock("Pets")

        try window.rename("Pets", to: "Animals")

        #expect(listening.stops == 1)
        #expect(window.mockServers.isEmpty)
        #expect(try raccoonJSON().mocks["Animals"] == nil)
    }

    @Test func `trashing the Collection stops its server`() async throws {
        let listening = ScriptedMockListening()
        let window = try setUp(listening)
        try await window.startMock("Pets")

        try window.trash("Pets")

        #expect(listening.stops == 1)
        #expect(window.mockServers.isEmpty)
    }

    @Test func `a Collection that vanished on disk stops its server on the next scan`() async throws {
        let listening = ScriptedMockListening()
        let window = try setUp(listening)
        try await window.startMock("Pets")
        try FileManager.default.removeItem(at: root.appending(path: "Pets"))

        watch.emit(["Pets"])
        for _ in 0..<50 { await Task.yield() }

        #expect(listening.stops == 1)
        #expect(window.mockServers.isEmpty)
    }

    @Test func `a change in another Collection leaves the server running`() async throws {
        let listening = ScriptedMockListening()
        let window = try setUp(listening)
        try await window.startMock("Pets")

        try window.rename("Other", to: "Else")

        #expect(listening.stops == 0)
        #expect(window.mockServers["Pets"] != nil)
    }

    /// A listener whose bind finishes only when the test lets it, to put other work inside the await.
    final class SlowListening: MockListening {
        let inner = ScriptedMockListening()
        let gate = AsyncStream<Void>.makeStream()

        func listen(port: UInt16?, handler: @escaping @Sendable (MockRequestHead) async -> MockReply) async throws(MockError) -> MockListener {
            let listener = try await inner.listen(port: port, handler: handler)
            for await _ in gate.stream { break }
            return listener
        }
    }

    @Test func `a start that a Workspace switch overtook stops its listener and registers nothing`() async throws {
        let slow = SlowListening()
        let slowWindow = try setUp(slow)
        let start = Task { try await slowWindow.startMock("Pets") }
        for _ in 0..<50 { await Task.yield() }
        let other = temp.appending(path: "Elsewhere")
        try FileManager.default.createDirectory(at: other, withIntermediateDirectories: true)
        await slowWindow.openWorkspace(other.path)

        slow.gate.continuation.yield()
        try await start.value

        #expect(slow.inner.stops == 1)
        #expect(slowWindow.mockServers.isEmpty)
    }
}

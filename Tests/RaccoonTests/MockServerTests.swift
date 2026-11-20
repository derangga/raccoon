import Foundation
@testable import Raccoon
import RaccoonData
import RaccoonDomain
import RaccoonTesting
import Synchronization
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

    // MARK: Settings changed while stopped or running

    @Test func `a remembered port is what the next start asks for`() async throws {
        let listening = ScriptedMockListening()
        let window = try setUp(listening)

        window.setMockPort("Pets", .port(3000))
        try await window.startMock("Pets")

        #expect(listening.requestedPorts == [3000])
        #expect(window.mockServers["Pets"]?.port == 3000)
    }

    @Test func `an automatic port asks the listener for none`() async throws {
        let existing = WorkspaceFile.encode(WorkspaceID(UUID()), mocks: ["Pets": MockSettings(port: 8081, allowsCORS: true)])
        let listening = ScriptedMockListening(picked: 50_004)
        let window = try setUp(listening, raccoonJSON: String(decoding: existing, as: UTF8.self))

        window.setMockPort("Pets", .automatic)
        try await window.startMock("Pets")

        #expect(listening.requestedPorts == [nil])
        #expect(window.mockServers["Pets"]?.port == 50_004)
    }

    @Test func `an invalid port is refused and writes nothing`() throws {
        let window = try setUp()
        let before = try Data(contentsOf: root.appending(path: "raccoon.json"))

        window.setMockPort("Pets", .invalid)

        #expect(window.mockSettings("Pets") == .standard)
        #expect(!window.hasMockSettings("Pets"))
        #expect(try Data(contentsOf: root.appending(path: "raccoon.json")) == before)
    }

    @Test func `setting the port keeps the remembered CORS and the other Collections`() throws {
        let existing = WorkspaceFile.encode(WorkspaceID(UUID()), mocks: ["Other": MockSettings(port: 9000, allowsCORS: false), "Pets": MockSettings(port: 8081, allowsCORS: false)])
        let window = try setUp(raccoonJSON: String(decoding: existing, as: UTF8.self))

        window.setMockPort("Pets", .port(3000))

        #expect(window.mockSettings("Pets") == MockSettings(port: 3000, allowsCORS: false))
        #expect(try raccoonJSON().mocks == ["Other": MockSettings(port: 9000, allowsCORS: false), "Pets": MockSettings(port: 3000, allowsCORS: false)])
    }

    @Test func `hasMockSettings is false with no entry and true once a port or CORS is set`() throws {
        let window = try setUp()
        #expect(!window.hasMockSettings("Pets"))
        #expect(!window.hasMockSettings("Other"))

        window.setMockAllowsCORS("Other", false)
        window.setMockPort("Pets", .automatic)

        #expect(window.hasMockSettings("Pets"))
        #expect(window.hasMockSettings("Other"))
        #expect(window.mockSettings("Other") == MockSettings(port: nil, allowsCORS: false))
    }

    @Test func `a raccoon json that cannot be written leaves hasMockSettings as the file says`() throws {
        let window = try setUp()
        try FileManager.default.removeItem(at: root.appending(path: "raccoon.json"))

        window.setMockPort("Pets", .port(3000))

        #expect(!window.hasMockSettings("Pets"))
        #expect(window.mockSettings("Pets") == .standard)
    }

    @Test func `a port set while running changes nothing until restart`() async throws {
        let listening = ScriptedMockListening()
        let window = try setUp(listening)
        try await window.startMock("Pets")

        window.setMockPort("Pets", .port(3001))

        #expect(listening.requestedPorts == [nil])
        #expect(listening.stops == 0)
        #expect(window.mockServers["Pets"]?.port == 50_000)
        #expect(window.mockSettings("Pets").port == 3001)
        #expect(try raccoonJSON().mocks["Pets"]?.port == 3001)
    }

    @Test func `restart stops the old listener, listens on the new port and remembers the bound one`() async throws {
        let listening = ScriptedMockListening()
        let window = try setUp(listening)
        try await window.startMock("Pets")
        window.setMockPort("Pets", .port(3001))

        try await window.restartMock("Pets")

        #expect(listening.stops == 1)
        #expect(listening.requestedPorts == [nil, 3001])
        #expect(window.mockServers["Pets"]?.port == 3001)
        #expect(try raccoonJSON().mocks["Pets"]?.port == 3001)
        #expect(await body(listening) == "[1]")
    }

    @Test func `restart onto an automatic port remembers the port the system picked`() async throws {
        let listening = ScriptedMockListening(picked: 50_005)
        let window = try setUp(listening)
        window.setMockPort("Pets", .port(3001))
        try await window.startMock("Pets")
        window.setMockPort("Pets", .automatic)

        try await window.restartMock("Pets")

        #expect(listening.requestedPorts == [3001, nil])
        #expect(window.mockServers["Pets"]?.port == 50_005)
        #expect(try raccoonJSON().mocks["Pets"]?.port == 50_005)
    }

    /// Binds the first listen and fails every one after it.
    final class FailsAfterFirst: MockListening {
        let inner = ScriptedMockListening()
        let failure: MockError
        let calls = Mutex(0)

        init(_ failure: MockError) { self.failure = failure }

        func listen(port: UInt16?, handler: @escaping @Sendable (MockRequestHead) async -> MockReply) async throws(MockError) -> MockListener {
            if calls.withLock({ defer { $0 += 1 }; return $0 }) > 0 { throw failure }
            return try await inner.listen(port: port, handler: handler)
        }
    }

    @Test func `a restart whose port is taken throws and leaves the server stopped`() async throws {
        let listening = FailsAfterFirst(.portInUse(3001))
        let window = try setUp(listening)
        try await window.startMock("Pets")
        window.setMockPort("Pets", .port(3001))

        await #expect(throws: MockError.portInUse(3001)) { try await window.restartMock("Pets") }

        #expect(listening.inner.stops == 1)
        #expect(window.mockServers.isEmpty)
    }

    @Test func `the CORS toggle keeps a remembered port that is not the bound one yet`() async throws {
        let listening = ScriptedMockListening()
        let window = try setUp(listening)
        try await window.startMock("Pets")
        window.setMockPort("Pets", .port(3001))

        window.setMockAllowsCORS("Pets", false)

        #expect(try raccoonJSON().mocks["Pets"] == MockSettings(port: 3001, allowsCORS: false))
        #expect(window.mockServers["Pets"]?.port == 50_000)
        #expect(window.mockServers["Pets"]?.allowsCORS == false)
    }

    @Test func `the CORS switch works while stopped and the next start uses it`() async throws {
        let listening = ScriptedMockListening()
        let window = try setUp(listening)

        window.setMockAllowsCORS("Pets", false)
        try await window.startMock("Pets")

        #expect(window.mockServers["Pets"]?.allowsCORS == false)
        #expect(try raccoonJSON().mocks["Pets"]?.allowsCORS == false)
    }

    @Test func `routes of a stopped Collection are readable and follow a save`() async throws {
        let window = try setUp()
        #expect(window.mockRoutes("Pets").count == 1)
        #expect(window.mockRoutes("Pets").first?.examples.first?.status == 200)
        #expect(window.mockRoutes("Other").isEmpty)
        #expect(window.mockRoutes("Nope").isEmpty)

        try window.updateExample(Self.requestID, Self.example("[2]", status: 201))

        #expect(window.mockServers.isEmpty)
        #expect(window.mockRoutes("Pets").first?.examples.first?.status == 201)
    }

    @Test func `route rows list every Request, with or without an Example, stopped or running`() async throws {
        let listening = ScriptedMockListening()
        let window = try setUp(listening)
        var bare = RequestDefinition.empty
        bare.method = "POST"
        bare.url = "{{baseUrl}}/v1/{{version}}/items?x=1"
        let bareID = RequestID(UUID(uuidString: "00000000-0000-4000-8000-0000000000A2")!)
        try RequestFile.encode(Request(id: bareID, name: "Add item", definition: bare, examples: []))
            .write(to: root.appending(path: "Pets/Add item.json"))
        window.loadDataFolder()

        let expected = [
            MockRouteRow(method: "GET", path: "/pets", exampleCount: 1),
            MockRouteRow(method: "POST", path: "/v1/{{version}}/items", exampleCount: 0),
        ]
        #expect(window.mockRouteRows("Pets").sorted { $0.method < $1.method } == expected)
        #expect(window.mockRouteRows("Other").isEmpty)
        #expect(window.mockRouteRows("Nope").isEmpty)

        try await window.startMock("Pets")

        #expect(window.mockRouteRows("Pets").sorted { $0.method < $1.method } == expected)
        #expect(window.mockServers["Pets"]?.routes.count == 1)
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

    @Test func `settings set on a Collection that is not there change nothing and write nothing`() throws {
        let window = try setUp()
        let before = try Data(contentsOf: root.appending(path: "raccoon.json"))

        window.setMockPort("Nope", .port(3000))
        window.setMockAllowsCORS("Nope", false)

        #expect(!window.hasMockSettings("Nope"))
        #expect(try Data(contentsOf: root.appending(path: "raccoon.json")) == before)
    }

    @Test func `a CORS toggle made while the bind is pending is the one that runs and is remembered`() async throws {
        let slow = SlowListening()
        let window = try setUp(slow)
        let start = Task { try await window.startMock("Pets") }
        for _ in 0..<50 { await Task.yield() }

        window.setMockAllowsCORS("Pets", false)
        slow.gate.continuation.yield()
        try await start.value

        #expect(window.mockServers["Pets"]?.allowsCORS == false)
        #expect(try raccoonJSON().mocks["Pets"] == MockSettings(port: 50_000, allowsCORS: false))
        let preflight = MockRequestHead(
            method: "OPTIONS", path: ["pets"],
            headers: [.init(name: "Access-Control-Request-Method", value: "GET")], bodyLength: 0)
        #expect(await slow.inner.answer(preflight)?.status != 204)
    }

    @Test func `overlapping starts listen once and the second returns without an error`() async throws {
        let slow = SlowListening()
        let window = try setUp(slow)
        let first = Task { try await window.startMock("Pets") }
        for _ in 0..<50 { await Task.yield() }
        #expect(window.mockStarting == ["Pets"])

        try await window.startMock("Pets")
        try await window.restartMock("Pets")
        slow.gate.continuation.yield()
        try await first.value

        #expect(slow.inner.requestedPorts.count == 1)
        #expect(slow.inner.stops == 0)
        #expect(window.mockStarting.isEmpty)
        #expect(window.mockServers["Pets"] != nil)
    }

    @Test func `a start that fails is no longer starting`() async throws {
        let window = try setUp(ScriptedMockListening(failing: .portInUse(8081)))

        await #expect(throws: MockError.portInUse(8081)) { try await window.startMock("Pets") }

        #expect(window.mockStarting.isEmpty)
    }
}

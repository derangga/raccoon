import Foundation
@testable import Raccoon
import RaccoonData
import RaccoonDomain
import RaccoonTesting
import Synchronization
import Testing

/// Binds only when the system picks the port: any asked-for port is "taken".
private final class TakenPorts: MockListening {
    func listen(port: UInt16?, handler: @escaping @Sendable (MockRequestHead) async -> MockReply) async throws(MockError) -> MockListener {
        guard port == nil else { throw .portInUse(port!) }
        return MockListener(port: 50_000, stop: {})
    }
}

/// Holds `listen` until the test lets it go, so the Starting state can be read.
private final class GatedListening: MockListening {
    private let waiting = Mutex<CheckedContinuation<Void, Never>?>(nil)
    private let entered = Mutex(false)

    var isWaiting: Bool { entered.withLock { $0 } }

    func release() { waiting.withLock { $0.take() }?.resume() }

    func listen(port: UInt16?, handler: @escaping @Sendable (MockRequestHead) async -> MockReply) async throws(MockError) -> MockListener {
        await withCheckedContinuation { continuation in
            waiting.withLock { $0 = continuation }
            entered.withLock { $0 = true }
        }
        return MockListener(port: port ?? 50_000, stop: {})
    }
}

/// The Mock Server sheet's decisions, over a live window and a scripted listener: every string,
/// button and message the view draws is read here, so the AppKit view holds none of them.
@MainActor
struct MockSheetModelTests {
    let temp = FileManager.default.temporaryDirectory.appending(path: "raccoon-\(UUID())")
    var root: URL { temp.appending(path: "Raccoon") }

    static let listID = RequestID(UUID(uuidString: "00000000-0000-4000-8000-0000000000A1")!)
    static let refundsID = RequestID(UUID(uuidString: "00000000-0000-4000-8000-0000000000A2")!)
    static let exampleID = ExampleID(UUID(uuidString: "00000000-0000-4000-8000-0000000000E1")!)

    static func example(_ body: String) -> Example { Example(id: exampleID, name: "ok", status: 200, body: .text(body)) }

    func write(_ id: RequestID, _ name: String, url: String, examples: [Example]) throws {
        let file = root.appending(path: "Pets/\(name).json")
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        var definition = RequestDefinition.empty
        definition.method = "GET"
        definition.url = url
        try RequestFile.encode(Request(id: id, name: name, definition: definition, examples: examples)).write(to: file)
    }

    /// Collection "Pets": `GET /pets` with an Example, `GET /refunds` with none.
    func makeWindow(_ listening: any MockListening, raccoonJSON: String? = nil) throws -> WindowModel {
        try write(Self.listID, "List pets", url: "https://api.example.com/pets", examples: [Self.example("[1]")])
        try write(Self.refundsID, "Refunds", url: "https://api.example.com/refunds", examples: [])
        if let raccoonJSON { try Data(raccoonJSON.utf8).write(to: root.appending(path: "raccoon.json")) }
        let window = WindowModel(
            dataFolder: .test(root), folderWatch: ManualFolderWatch(),
            sessionStore: DiskSessionStore(directory: temp.appending(path: "Support"), root: root.path), secrets: InMemorySecretStore(),
            instants: FixedInstantSource(.now), mockListening: listening,
            makeTab: {
                TabModel(transport: ScriptedTransport(.failure(.timedOut(seconds: 60))), secrets: InMemorySecretStore(), files: DictionaryFileReading([:]),
                         instants: FixedInstantSource(.now), clipboard: RecordingClipboardWriter())
            }
        )
        window.loadDataFolder()
        return window
    }

    func sheet(
        _ window: WindowModel, failure: MockError? = nil, clipboard: RecordingClipboardWriter = RecordingClipboardWriter()
    ) -> MockSheetModel {
        MockSheetModel(window: window, collection: "Pets", failure: failure, clipboard: clipboard)
    }

    // MARK: Stopped

    @Test func `a stopped Collection reads Not running with Start the default and the port empty`() throws {
        let model = sheet(try makeWindow(ScriptedMockListening()))

        #expect(model.state == .stopped)
        #expect(model.statusText == "Not running")
        #expect(model.portText == "")
        #expect(model.portMessage == "Use a port from 1024 to 65535, or leave it empty and Raccoon picks one.")
        #expect(model.actions == [.cancel, .start])
        #expect(model.defaultAction == .start)
        #expect(model.isEnabled(.start))
        #expect(model.allowsCORS)
    }

    @Test func `the field starts from the remembered port and CORS`() throws {
        let json = WorkspaceFile.encode(WorkspaceID(UUID()), mocks: ["Pets": MockSettings(port: 8081, allowsCORS: false)])
        let model = sheet(try makeWindow(ScriptedMockListening(), raccoonJSON: String(decoding: json, as: UTF8.self)))

        #expect(model.portText == "8081")
        #expect(!model.allowsCORS)
    }

    @Test(arguments: ["80", "1023", "65536", "abc", "30 00", "-3000"])
    func `a port outside 1024 to 65535 blocks Start and says why`(text: String) async throws {
        let listening = ScriptedMockListening()
        let model = sheet(try makeWindow(listening))

        model.editPort(text)
        await model.start()

        #expect(model.portNote == .invalid)
        #expect(model.portMessage == "Use a port from 1024 to 65535.")
        #expect(model.portMessageIsError)
        #expect(!model.isEnabled(.start))
        #expect(listening.requestedPorts.isEmpty)
        #expect(model.state == .stopped)
    }

    @Test func `a keystroke that parses is remembered and one that does not is not`() throws {
        let window = try makeWindow(ScriptedMockListening())
        let model = sheet(window)

        model.editPort("3000")
        #expect(window.mockSettings("Pets").port == 3000)
        model.editPort("30000000")
        #expect(window.mockSettings("Pets").port == 3000)
        model.editPort("")
        #expect(window.mockSettings("Pets").port == nil)
    }

    // MARK: Start

    @Test func `Start runs on the field's port and Done becomes the default`() async throws {
        let listening = ScriptedMockListening()
        let model = sheet(try makeWindow(listening))
        model.editPort("3000")

        await model.start()

        #expect(listening.requestedPorts == [3000])
        #expect(model.state == .running(port: 3000))
        #expect(model.statusText == "Running at http://127.0.0.1:3000")
        #expect(model.statusURL == "http://127.0.0.1:3000")
        #expect(model.actions == [.stop, .done])
        #expect(model.defaultAction == .done)
        #expect(model.portNote == .hint)
    }

    @Test func `an empty field starts on a free port and the field then shows it`() async throws {
        let listening = ScriptedMockListening(picked: 50_007)
        let model = sheet(try makeWindow(listening))

        await model.start()

        #expect(listening.requestedPorts == [nil])
        #expect(model.state == .running(port: 50_007))
        #expect(model.portText == "50007")
        #expect(model.portNote == .hint)
    }

    @Test func `a start in flight reads Starting, takes no clicks and a second Start starts nothing`() async throws {
        let gate = GatedListening()
        let model = sheet(try makeWindow(gate))

        let starting = Task { await model.start() }
        while !gate.isWaiting { await Task.yield() }
        await model.start()

        #expect(model.state == .starting)
        #expect(model.statusText == "Starting…")
        #expect(model.actions == [.cancel, .start])
        #expect(!model.isEnabled(.start))
        #expect(!model.isEnabled(.cancel))

        gate.release()
        await starting.value
        #expect(model.state == .running(port: 50_000))
    }

    @Test func `a sheet opened while the menu's start is in flight reads Starting and takes no clicks`() async throws {
        let gate = GatedListening()
        let window = try makeWindow(gate)
        let starting = Task { try await window.startMock("Pets") }
        while !gate.isWaiting { await Task.yield() }

        let model = sheet(window)
        await model.start()

        #expect(model.state == .starting)
        #expect(!model.isEnabled(.start))

        gate.release()
        try await starting.value
        #expect(model.state == .running(port: 50_000))
    }

    // MARK: Failures

    @Test func `a taken port shows under the field, and use any free port starts on another`() async throws {
        let model = sheet(try makeWindow(TakenPorts()))
        model.editPort("3000")

        await model.start()

        #expect(model.state == .failed(.portInUse(3000)))
        #expect(model.portNote == .inUse(3000))
        #expect(model.portMessage == "Port 3000 is in use. Choose another port, or")
        #expect(model.portMessageIsError)
        #expect(model.showsUseAnyFreePort)
        #expect(model.statusText == "Not running")
        #expect(!model.statusIsError)
        #expect(model.actions == [.cancel, .start])

        await model.useAnyFreePort()

        #expect(model.state == .running(port: 50_000))
        #expect(model.portText == "50000")
        #expect(!model.showsUseAnyFreePort)
    }

    @Test func `use any free port does nothing unless the port was taken`() async throws {
        let listening = ScriptedMockListening()
        let model = sheet(try makeWindow(listening))

        await model.useAnyFreePort()

        #expect(listening.requestedPorts.isEmpty)
    }

    @Test func `typing a port that parses clears the taken-port message`() async throws {
        let model = sheet(try makeWindow(TakenPorts()))
        model.editPort("3000")
        await model.start()

        model.editPort("3001")

        #expect(model.state == .stopped)
        #expect(model.portNote == .hint)
    }

    @Test func `another failure shows under the status in red and the field keeps its hint`() async throws {
        let model = sheet(try makeWindow(ScriptedMockListening(failing: .failed("denied"))))

        await model.start()

        #expect(model.state == .failed(.failed("denied")))
        #expect(model.statusText == "Couldn't start the Mock Server: denied.")
        #expect(model.statusIsError)
        #expect(model.portNote == .hint)
        #expect(!model.showsUseAnyFreePort)
        #expect(model.actions == [.cancel, .start])
        #expect(model.isEnabled(.start))
    }

    @Test func `a start that just failed shows as if the sheet had started it`() throws {
        let window = try makeWindow(ScriptedMockListening())

        let taken = sheet(window, failure: .portInUse(3000))
        #expect(taken.state == .failed(.portInUse(3000)))
        #expect(taken.portMessage == "Port 3000 is in use. Choose another port, or")

        let other = sheet(window, failure: .failed("denied"))
        #expect(other.state == .failed(.failed("denied")))
        #expect(other.statusText == "Couldn't start the Mock Server: denied.")
    }

    // MARK: Running

    @Test func `editing the port while running offers Restart and leaves the bound port alone`() async throws {
        let window = try makeWindow(ScriptedMockListening())
        let model = sheet(window)
        model.editPort("3000")
        await model.start()

        model.editPort("3001")

        #expect(model.state == .running(port: 3000))
        #expect(window.mockServers["Pets"]?.port == 3000)
        #expect(model.portNote == .restart(.port(3001)))
        #expect(model.portMessage == "Restart to use port 3001.")
        #expect(!model.portMessageIsError)
        #expect(model.actions == [.stop, .restart, .done])
        #expect(model.defaultAction == .restart)

        model.editPort("")
        #expect(model.portMessage == "Restart to use any free port.")
        #expect(model.actions == [.stop, .restart, .done])

        model.editPort("3000")
        #expect(model.portNote == .hint)
        #expect(model.actions == [.stop, .done])
        #expect(model.defaultAction == .done)

        model.editPort("80")
        #expect(model.portNote == .invalid)
        #expect(model.actions == [.stop, .done])
        #expect(model.defaultAction == .done)
    }

    @Test func `Restart binds the new port`() async throws {
        let listening = ScriptedMockListening()
        let model = sheet(try makeWindow(listening))
        model.editPort("3000")
        await model.start()
        model.editPort("3001")

        await model.restart()

        #expect(listening.requestedPorts == [3000, 3001])
        #expect(listening.stops == 1)
        #expect(model.state == .running(port: 3001))
        #expect(model.portNote == .hint)
        #expect(model.actions == [.stop, .done])
    }

    @Test func `a Restart onto a taken port stops the server and shows the port taken`() async throws {
        let listening = TakenPortsAfterFirst()
        let model = sheet(try makeWindow(listening))
        model.editPort("3000")
        await model.start()
        model.editPort("3001")

        await model.restart()

        #expect(model.state == .failed(.portInUse(3001)))
        #expect(model.portMessage == "Port 3001 is in use. Choose another port, or")
    }

    @Test func `Restart does nothing while the field matches the bound port`() async throws {
        let listening = ScriptedMockListening()
        let model = sheet(try makeWindow(listening))
        model.editPort("3000")
        await model.start()

        await model.restart()

        #expect(listening.requestedPorts == [3000])
    }

    @Test func `Stop closes the server and the sheet reads Not running`() async throws {
        let listening = ScriptedMockListening()
        let model = sheet(try makeWindow(listening))
        await model.start()

        model.stop()

        #expect(listening.stops == 1)
        #expect(model.state == .stopped)
        #expect(model.statusText == "Not running")
        #expect(model.actions == [.cancel, .start])
    }

    @Test func `a Stop from outside the sheet updates it`() async throws {
        let window = try makeWindow(ScriptedMockListening())
        let model = sheet(window)
        await model.start()

        window.stopMock("Pets")

        #expect(model.state == .stopped)
    }

    @Test func `a server started from outside the sheet shows as running`() async throws {
        let window = try makeWindow(ScriptedMockListening(picked: 50_009))
        let model = sheet(window)

        try await window.startMock("Pets")

        #expect(model.state == .running(port: 50_009))
    }

    // MARK: Collection gone

    @Test func `the Collection is there until it is renamed, trashed or the Workspace is switched`() async throws {
        let window = try makeWindow(ScriptedMockListening())
        let model = sheet(window)
        #expect(!model.isCollectionGone)

        try window.rename("Pets", to: "Animals")
        #expect(model.isCollectionGone)
    }

    @Test func `trashing the Collection shows it gone`() throws {
        let window = try makeWindow(ScriptedMockListening())
        let model = sheet(window)

        try window.trash("Pets")

        #expect(model.isCollectionGone)
    }

    @Test func `a Workspace switch shows the Collection gone`() async throws {
        let window = try makeWindow(ScriptedMockListening())
        let model = sheet(window)
        let other = temp.appending(path: "Elsewhere")
        try FileManager.default.createDirectory(at: other, withIntermediateDirectories: true)

        await window.openWorkspace(other.path)

        #expect(model.isCollectionGone)
    }

    // MARK: CORS

    @Test func `CORS toggles while stopped and is remembered`() throws {
        let window = try makeWindow(ScriptedMockListening())
        let model = sheet(window)

        model.setAllowsCORS(false)

        #expect(!model.allowsCORS)
        #expect(!window.mockSettings("Pets").allowsCORS)
    }

    @Test func `CORS toggles while running and the next reply follows with no restart`() async throws {
        let listening = ScriptedMockListening()
        let window = try makeWindow(listening)
        let model = sheet(window)
        await model.start()
        let preflight = MockRequestHead(
            method: "OPTIONS", path: ["pets"], headers: [.init(name: "Access-Control-Request-Method", value: "GET")], bodyLength: 0)
        #expect(await listening.answer(preflight)?.status == 204)

        model.setAllowsCORS(false)

        #expect(!model.allowsCORS)
        #expect(await listening.answer(preflight)?.status != 204)
        #expect(listening.requestedPorts.count == 1)
    }

    // MARK: Routes

    @Test func `the routes read from the files before anything starts, an empty Request says so`() throws {
        let model = sheet(try makeWindow(ScriptedMockListening()))

        #expect(model.routesHeading == "Serving 1 of 2 Requests")
        #expect(model.routeLines == [
            MockRouteLine(method: "GET", path: "/pets", detail: "1 Example", isServed: true),
            MockRouteLine(method: "GET", path: "/refunds", detail: "Add an Example to serve it.", isServed: false),
        ])
        #expect(model.routesEmptyText == nil)
    }

    @Test func `the routes follow a save`() throws {
        let window = try makeWindow(ScriptedMockListening())
        let model = sheet(window)

        try window.updateExample(Self.refundsID, Self.example("[]"))

        #expect(model.routesHeading == "Serving 2 of 2 Requests")
        #expect(model.routeLines.map(\.detail) == ["1 Example", "1 Example"])
    }

    @Test func `no Requests reads the one sentence`() throws {
        let window = try makeWindow(ScriptedMockListening())
        let model = MockSheetModel(window: window, collection: "Other", failure: nil, clipboard: RecordingClipboardWriter())

        #expect(model.routeLines.isEmpty)
        #expect(model.routesEmptyText == "Nothing to serve yet. Save a Response as an Example to start.")
    }

    @Test func `the Example count is singular for one and plural for more`() {
        #expect(MockRouteLine(MockRouteRow(method: "GET", path: "/a", exampleCount: 2)).detail == "2 Examples")
        #expect(MockRouteLine(MockRouteRow(method: "GET", path: "/a", exampleCount: 1)).detail == "1 Example")
        #expect(MockRouteLine(MockRouteRow(method: "GET", path: "/a", exampleCount: 0)).detail == "Add an Example to serve it.")
    }

    // MARK: Copy URL

    @Test func `Copy URL copies the address and reads Copied`() async throws {
        let clipboard = RecordingClipboardWriter()
        let model = sheet(try makeWindow(ScriptedMockListening()), clipboard: clipboard)
        model.editPort("3000")
        await model.start()

        model.copyURL()

        #expect(clipboard.string == "http://127.0.0.1:3000")
        #expect(model.copied)
    }

    @Test func `Copy URL while stopped copies nothing`() throws {
        let clipboard = RecordingClipboardWriter()
        let model = sheet(try makeWindow(ScriptedMockListening()), clipboard: clipboard)

        model.copyURL()

        #expect(clipboard.string == nil)
        #expect(!model.copied)
    }
}

/// The first bind works; any later one finds its port taken.
private final class TakenPortsAfterFirst: MockListening {
    private let count = Mutex(0)

    func listen(port: UInt16?, handler: @escaping @Sendable (MockRequestHead) async -> MockReply) async throws(MockError) -> MockListener {
        let n = count.withLock { value in value += 1; return value }
        if n > 1, let port { throw .portInUse(port) }
        return MockListener(port: port ?? 50_000, stop: {})
    }
}

import Foundation
@testable import RaccoonDomain
import RaccoonTesting
import Testing

struct TestPortsTests {
    let resolved = ResolvedRequest(definition: RequestDefinition(
        method: "POST", url: "https://example.com/a", params: [], headers: [], cookies: [],
        body: .raw(.json, "{}"), auth: .none, settings: RequestDefinition.empty.settings
    ), url: URL(string: "https://example.com/a")!)

    @Test func `scripted transport returns its Response and records the request`() async throws {
        let response = Response(status: 201, headers: [.init(name: "A", value: "1")], body: Data("ok".utf8), elapsed: .milliseconds(5), byteCount: 2)
        let transport = ScriptedTransport(.success(response))

        #expect(try await transport.send(resolved) == response)
        #expect(transport.requests == [resolved])
    }

    @Test func `scripted transport throws its SendError and still records the request`() async {
        let transport = ScriptedTransport(.failure(.timedOut))

        await #expect(throws: SendError.timedOut) { try await transport.send(resolved) }
        #expect(transport.requests == [resolved])
    }

    @Test func `dictionary file reading returns the bytes it was given`() throws {
        let files = DictionaryFileReading(["/tmp/a.json": Data("{}".utf8)])

        #expect(try files.read("/tmp/a.json") == Data("{}".utf8))
        #expect(throws: StoreError.unreadable(path: "/tmp/b", reason: "No such file")) { try files.read("/tmp/b") }
    }

    @Test func `recording file writing keeps every write in order`() throws {
        let files = RecordingFileWriting()
        let a = URL(filePath: "/tmp/a.json"), b = URL(filePath: "/tmp/b.json")

        try files.write(Data("1".utf8), to: a)
        try files.write(Data("2".utf8), to: b)
        try files.write(Data("3".utf8), to: a)

        #expect(files.writes.map(\.url) == [a, b, a])
        #expect(files.writes.map(\.data) == [Data("1".utf8), Data("2".utf8), Data("3".utf8)])
    }

    @Test func `recording file writing throws the StoreError set for a URL and records nothing`() {
        let a = URL(filePath: "/tmp/a.json"), b = URL(filePath: "/tmp/b.json")
        let failure = StoreError.unwritable(path: a.path, reason: "permission denied")
        let files = RecordingFileWriting(failing: [a: failure])

        #expect(throws: failure) { try files.write(Data("1".utf8), to: a) }
        #expect(throws: Never.self) { try files.write(Data("2".utf8), to: b) }
        #expect(files.writes.map(\.url) == [b])
    }

    @Test func `manual folder watch delivers what the test emits`() async {
        let watch = ManualFolderWatch()
        var events = watch.events(root: "/root").makeAsyncIterator()

        watch.emit(["a.json", "b/c.json"])
        watch.emit(["d.json"])

        #expect(await events.next() == ["a.json", "b/c.json"])
        #expect(await events.next() == ["d.json"])
    }

    @Test func `in-memory secret store keeps values per Environment and name`() throws {
        let secrets = InMemorySecretStore()
        let token = try #require(VariableName("token"))

        try secrets.set("prod-1", environment: "Prod", name: token)
        try secrets.set("global-1", environment: nil, name: token)
        #expect(try secrets.get(environment: "Prod", name: token) == "prod-1")
        #expect(try secrets.get(environment: nil, name: token) == "global-1")
        #expect(try secrets.get(environment: "Dev", name: token) == nil)

        try secrets.delete(environment: "Prod", name: token)
        #expect(try secrets.get(environment: "Prod", name: token) == nil)
    }

    @Test func `recording clipboard writer keeps the last string`() {
        let clipboard = RecordingClipboardWriter()

        clipboard.setString("curl a")
        clipboard.setString("curl b")

        #expect(clipboard.string == "curl b")
    }

    @Test func `fixed instant source returns the instant it was given`() {
        let instant = ContinuousClock.now
        let clock = FixedInstantSource(instant)

        #expect(clock.now == instant)
        #expect(clock.now == instant)
    }
}

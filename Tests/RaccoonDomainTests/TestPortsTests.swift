import Foundation
@testable import RaccoonDomain
import RaccoonTesting
import Testing

struct TestPortsTests {
    let resolved = ResolvedRequest(definition: RequestDefinition(
        method: "POST", url: "https://example.com/a", params: [], headers: [], cookies: [],
        body: .raw(.json, "{}"), auth: .none, settings: RequestDefinition.empty.settings
    ))

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

    @Test func `recording pasteboard keeps the last string`() {
        let pasteboard = RecordingPasteboard()

        pasteboard.setString("curl a")
        pasteboard.setString("curl b")

        #expect(pasteboard.string == "curl b")
    }

    @Test func `fixed instant source returns the instant it was given`() {
        let instant = ContinuousClock.now
        let clock = FixedInstantSource(instant)

        #expect(clock.now == instant)
        #expect(clock.now == instant)
    }
}

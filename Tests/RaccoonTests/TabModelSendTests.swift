import Foundation
@testable import Raccoon
import RaccoonDomain
import RaccoonTesting
import Testing

@MainActor
struct TabModelSendTests {
    let now = ContinuousClock.now
    let response = Response(status: 200, headers: [], body: Data("hello".utf8), elapsed: .milliseconds(5), byteCount: 5)

    func makeTab(_ transport: ScriptedTransport, url: String) -> TabModel {
        let model = TabModel(transport: transport, secrets: InMemorySecretStore(), instants: FixedInstantSource(now))
        model.tab.definition.url = url
        return model
    }

    @Test func `send resolves the URL, shows sending, then the received Response`() async {
        let transport = ScriptedTransport(.success(response))
        let model = makeTab(transport, url: "http://localhost:8080/")

        model.send()
        #expect(model.tab.response == .sending(since: now))
        await model.inFlight?.value

        #expect(transport.requests.map(\.url) == [URL(string: "http://localhost:8080/")])
        #expect(transport.requests.map(\.definition.method) == ["GET"])
        #expect(model.tab.response == .received(response))
        #expect(model.inFlight == nil)
    }

    @Test func `a send error lands in the Response state`() async {
        let model = makeTab(ScriptedTransport(.failure(.timedOut)), url: "http://localhost:8080/")

        model.send()
        await model.inFlight?.value

        #expect(model.tab.response == .failed(.timedOut, after: .zero))
    }

    @Test func `a URL that cannot be built sends nothing and never shows sending`() {
        let transport = ScriptedTransport(.success(response))
        let model = makeTab(transport, url: "not a url")

        model.send()

        #expect(model.tab.response == .notSent(.invalidURL("not a url")))
        #expect(model.inFlight == nil)
        #expect(transport.requests.isEmpty)
    }

    @Test func `a second send while one is in flight sends nothing`() async {
        let transport = ScriptedTransport(.success(response))
        let model = makeTab(transport, url: "http://localhost:8080/")

        model.send()
        model.send()
        await model.inFlight?.value

        #expect(transport.requests.count == 1)
    }

    @Test(arguments: [
        SendError.fileMissing(path: "/tmp/gone.pdf"), .timedOut, .untrustedCertificate(host: "localhost"),
        .transport(.cannotConnectToHost, "Could not connect to the server.", host: "localhost:8080"),
    ])
    func `a send error is shown as it came and never retried`(error: SendError) async {
        let transport = ScriptedTransport(.failure(error))
        let model = makeTab(transport, url: "http://localhost:8080/")

        model.send()
        await model.inFlight?.value

        #expect(model.tab.response == .failed(error, after: .zero))
        #expect(transport.requests.count == 1)
    }

    @Test func `the spinner stays hidden at the instant the send starts`() {
        let model = makeTab(ScriptedTransport(.success(response)), url: "http://localhost:8080/")

        model.send()

        #expect(model.tab.response == .sending(since: now))
        #expect(!model.showsSpinner)
    }

    @Test func `a received body is presented off the main actor and kept with the Tab`() async {
        let json = Response(status: 200, headers: [], body: Data(#"{"a":1}"#.utf8), elapsed: .milliseconds(5), byteCount: 7)
        let model = makeTab(ScriptedTransport(.success(json)), url: "http://localhost:8080/")

        model.send()
        await model.inFlight?.value
        await model.presenting?.value

        #expect(model.presented?.body == .pretty("{\n  \"a\": 1\n}", .json))
        #expect(model.presented?.ranges.isEmpty == false)
    }

    @Test func `a new send drops the old presentation`() async {
        let model = makeTab(ScriptedTransport(.success(response)), url: "http://localhost:8080/")
        model.send()
        await model.inFlight?.value
        await model.presenting?.value
        #expect(model.presented?.body == .raw("hello"))

        model.send()
        #expect(model.presented == nil)
    }

    @Test func `cancel returns the Tab to idle and keeps no Response`() async {
        let model = makeTab(ScriptedTransport(.success(response)), url: "http://localhost:8080/")

        model.send()
        let send = model.inFlight
        model.cancel()
        await send?.value

        #expect(model.tab.response == .idle)
        #expect(model.inFlight == nil && model.presented == nil)
    }

    @Test func `a send right after cancel goes out and keeps its own Response`() async {
        let transport = ScriptedTransport(.success(response))
        let model = makeTab(transport, url: "http://localhost:8080/")

        model.send()
        let cancelled = model.inFlight
        model.cancel()
        model.send()
        let second = model.inFlight
        await cancelled?.value
        await second?.value

        #expect(transport.requests.count == 2)
        #expect(model.tab.response == .received(response))
    }

    @Test func `cancel with nothing in flight changes nothing`() async {
        let model = makeTab(ScriptedTransport(.success(response)), url: "http://localhost:8080/")
        model.send()
        await model.inFlight?.value

        model.cancel()

        #expect(model.tab.response == .received(response))
    }

    @Test func `Allow insecure TLS turns the Request Setting on and sends nothing`() {
        let transport = ScriptedTransport(.success(response))
        let model = makeTab(transport, url: "https://localhost/")
        model.tab.response = .failed(.untrustedCertificate(host: "localhost"), after: .milliseconds(212))

        model.allowInsecureTLS()

        #expect(model.tab.definition.settings.allowsInsecureTLS)
        #expect(transport.requests.isEmpty)
        #expect(model.tab.response == .failed(.untrustedCertificate(host: "localhost"), after: .milliseconds(212)))
    }

    @Test func `an invalid URL marks the URL field until the next edit`() {
        let model = makeTab(ScriptedTransport(.success(response)), url: "not a url")

        model.send()
        #expect(model.isURLInvalid)

        model.typeInURLBar("http://localhost/")
        #expect(!model.isURLInvalid)
    }
}

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

        #expect(model.tab.response == .failed(.timedOut))
    }

    @Test func `a URL that cannot be built sends nothing and never shows sending`() {
        let transport = ScriptedTransport(.success(response))
        let model = makeTab(transport, url: "not a url")

        model.send()

        #expect(model.tab.response == .notSent(.invalidURL("not a url")))
        #expect(model.inFlight == nil)
        #expect(transport.requests.isEmpty)
    }
}

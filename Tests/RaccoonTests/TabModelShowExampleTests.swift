import Foundation
@testable import Raccoon
import RaccoonDomain
import RaccoonTesting
import Testing

/// An Example shown in a Request Tab's Response viewer, and Clear Response (examples.md §Show an Example).
@MainActor
struct TabModelShowExampleTests {
    let now = ContinuousClock.now
    let live = Response(status: 200, headers: [], body: Data("live".utf8), elapsed: .milliseconds(5), byteCount: 4)
    let example = Example(
        id: ExampleID(UUID()), name: "Created", status: 201,
        headers: [Row(name: "Content-Type", value: "application/json")], body: .text(#"{"id":1}"#))
    let clipboard = RecordingClipboardWriter()

    func makeTab(_ result: Result<Response, SendError>) -> TabModel {
        let model = TabModel(transport: ScriptedTransport(result), secrets: InMemorySecretStore(), files: DictionaryFileReading([:]),
                             instants: FixedInstantSource(now), clipboard: clipboard)
        model.tab.definition.url = "http://localhost:8080/"
        return model
    }

    @Test func `showing an Example shows it as the Response, and a live Response is replaced, not kept`() async {
        let model = makeTab(.success(live))
        model.send()
        await model.inFlight?.value

        model.show(example)

        #expect(model.shownExample == example)
        #expect(model.displayed == .received(example.asResponse))
        #expect(model.tab.response == .idle)
    }

    @Test func `the shown Example is presented like a Response: Pretty, and Copy copies it`() async {
        let model = makeTab(.success(live))

        model.show(example)
        await model.presenting?.value
        model.copyBody(pretty: true)

        #expect(model.presented != nil)
        #expect(clipboard.string == "{\n  \"id\": 1\n}")
        #expect(model.canSaveBody)
    }

    @Test func `showing an Example while a send is in flight leaves the send running, and its result replaces the Example`() async {
        let model = makeTab(.success(live))
        model.send()

        model.show(example)

        #expect(model.tab.response == .sending(since: now))
        #expect(model.displayed == .received(example.asResponse))
        await model.inFlight?.value
        #expect(model.shownExample == nil)
        #expect(model.displayed == .received(live))
        #expect(model.tab.response == .received(live))
    }

    @Test func `a failed send replaces the shown Example too`() async {
        let model = makeTab(.failure(.timedOut(seconds: 60)))
        model.send()
        model.show(example)

        await model.inFlight?.value

        #expect(model.shownExample == nil)
        #expect(model.displayed == .failed(.timedOut(seconds: 60), after: .zero))
    }

    @Test func `Send takes the Example off the viewer at once`() {
        let model = makeTab(.success(live))
        model.show(example)

        model.send()

        #expect(model.shownExample == nil)
        #expect(model.displayed == .sending(since: now))
    }

    @Test func `a Send that cannot be resolved takes the Example off too, and says why`() {
        let model = makeTab(.success(live))
        model.tab.definition.url = "not a url"
        model.show(example)

        model.send()

        #expect(model.shownExample == nil)
        #expect(model.displayed == .notSent(.invalidURL("not a url")))
    }

    @Test func `a Send with undefined variables sends nothing, so the Example stays`() {
        let model = makeTab(.success(live))
        model.tab.definition.url = "http://localhost:8080/{{missing}}"
        model.show(example)

        model.send()

        #expect(model.shownExample == example)
    }

    @Test func `showing an Example clears a stale failed-save note`() {
        let model = makeTab(.success(live))
        model.exampleNote = "Couldn't save the Example: the disk is full."

        model.show(example)

        #expect(model.exampleNote == nil)
    }

    @Test func `the sends after an Example is shown still present their Response`() async {
        let model = makeTab(.success(live))
        model.send()
        model.show(example)
        await model.inFlight?.value
        await model.presenting?.value

        #expect(model.presented?.body == .raw("live"))
    }

    @Test func `Clear Response empties a live Response`() async {
        let model = makeTab(.success(live))
        model.send()
        await model.inFlight?.value
        #expect(model.canClearResponse)

        model.clearResponse()

        #expect(model.tab.response == .idle)
        #expect(model.displayed == .idle)
        #expect(model.presented == nil)
        #expect(!model.canClearResponse)
    }

    @Test func `Clear Response empties a shown Example`() {
        let model = makeTab(.success(live))
        model.show(example)
        #expect(model.canClearResponse)

        model.clearResponse()

        #expect(model.shownExample == nil)
        #expect(model.displayed == .idle)
    }

    @Test func `Clear Response is off with nothing to clear, and while a send is in flight`() {
        let model = makeTab(.success(live))
        #expect(!model.canClearResponse)

        model.send()
        model.show(example)
        #expect(!model.canClearResponse)
        model.clearResponse()

        #expect(model.tab.response == .sending(since: now))
        #expect(model.shownExample == example)
    }

    @Test func `Clear Response empties a failed send too`() async {
        let model = makeTab(.failure(.timedOut(seconds: 60)))
        model.send()
        await model.inFlight?.value

        model.clearResponse()

        #expect(model.displayed == .idle)
    }
}

@testable import Raccoon
import RaccoonDomain
import RaccoonTesting
import Testing

/// pickBodyType changes the method, the headers and the body in one assignment.
@MainActor
struct PickBodyTypeTests {
    func model(method: String, body: Body, headers: [Row] = []) -> TabModel {
        let model = TabModel(transport: ScriptedTransport(.failure(.timedOut(seconds: 60))), secrets: InMemorySecretStore(), files: DictionaryFileReading([:]),
                             instants: FixedInstantSource(.now), clipboard: RecordingClipboardWriter())
        model.tab.definition.method = method
        model.tab.definition.body = body
        model.tab.definition.headers = headers
        return model
    }

    static let json = Row(name: "Content-Type", value: "application/json")
    static let text = Row(name: "Content-Type", value: "text/plain")

    @Test(arguments: [("GET", "POST"), ("HEAD", "POST"), ("PUT", "PUT"), ("POST", "POST")])
    func `picking GraphQL sets POST over GET and HEAD, converting the body and the Content-Type with it`(method: String, result: String) {
        let model = model(method: method, body: .raw(.text, #"{"query":"{ a }"}"#), headers: [Self.text])
        model.pickBodyType(.graphql)
        #expect(model.tab.definition.method == result)
        #expect(model.tab.definition.body == .graphql(GraphQLBody(query: "", variables: "", operationName: "")))
        #expect(model.tab.definition.headers == [Self.json])
    }

    @Test func `one pick changes the method, the headers and the body together`() {
        let model = model(method: "GET", body: .raw(.json, #"{"query":"{ a }","operationName":"Q"}"#), headers: [Self.json])
        model.pickBodyType(.graphql)
        #expect(model.tab.definition.method == "POST")
        #expect(model.tab.definition.body == .graphql(GraphQLBody(query: "{ a }", variables: "", operationName: "Q")))
        #expect(model.tab.definition.headers == [Self.json])
    }

    @Test func `a Content-Type the user set is kept`() {
        let custom = Row(name: "Content-Type", value: "application/graphql-response+json")
        let model = model(method: "GET", body: .raw(.json, "{}"), headers: [custom])
        model.pickBodyType(.graphql)
        #expect(model.tab.definition.headers == [custom])
    }

    @Test func `leaving GraphQL leaves the method alone`() {
        let model = model(method: "GET", body: .graphql(GraphQLBody(query: "{ a }", variables: "", operationName: "")), headers: [Self.json])
        model.pickBodyType(.raw(.json))
        #expect(model.tab.definition.method == "GET")
        #expect(model.tab.definition.body == .raw(.json, #"{"query":"{ a }"}"#))
    }
}

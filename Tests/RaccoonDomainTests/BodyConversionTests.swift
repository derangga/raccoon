import RaccoonDomain
import Testing

struct BodyConversionTests {
    static let raw = Body.raw(.json, "{\"a\": 1}")
    static let form = Body.formURLEncoded([Row(name: "a", value: "1"), Row(name: "b", value: "2", isEnabled: false)])
    static let multipart = Body.multipart([
        Part(name: "a", content: .text("1")),
        Part(name: "f", content: .file(path: "/tmp/f.png")),
        Part(name: "b", isEnabled: false, content: .text("2")),
    ])

    @Test(arguments: [
        (raw, BodyType.raw(.xml), Body.raw(.xml, "{\"a\": 1}")),
        (raw, .raw(.json), raw),
        (raw, .formURLEncoded, .formURLEncoded([])),
        (raw, .multipart, .multipart([])),
        (raw, .none, .none),
        (form, .multipart, .multipart([Part(name: "a", content: .text("1")), Part(name: "b", isEnabled: false, content: .text("2"))])),
        (form, .formURLEncoded, form),
        (form, .raw(.text), .raw(.text, "")),
        (form, .none, .none),
        (multipart, .formURLEncoded, form),
        (multipart, .multipart, multipart),
        (multipart, .raw(.json), .raw(.json, "")),
        (multipart, .none, .none),
        (Body.none, .raw(.json), .raw(.json, "")),
        (Body.none, .formURLEncoded, .formURLEncoded([])),
        (Body.none, .multipart, .multipart([])),
        (Body.none, .none, .none),
        (Body.none, .graphql, empty),
        (form, .graphql, empty),
        (multipart, .graphql, empty),
        (Body.raw(.text, "{\"query\": \"{ a }\"}"), .graphql, empty),
        (Body.raw(.xml, "<a/>"), .graphql, empty),
        (graphql, .graphql, graphql),
        (graphql, .none, .none),
        (graphql, .formURLEncoded, .formURLEncoded([])),
        (graphql, .multipart, .multipart([])),
        (graphql, .raw(.text), .raw(.text, "")),
        (graphql, .raw(.xml), .raw(.xml, "")),
        (graphql, .raw(.json), .raw(.json, "{\"query\":\"query Q { a }\",\"variables\":{\"id\": 1},\"operationName\":\"Q\"}")),
        (Body.graphql(GraphQLBody(query: "{ a }", variables: "", operationName: "")), .raw(.json), .raw(.json, "{\"query\":\"{ a }\"}")),
        (empty, .raw(.json), .raw(.json, "{\"query\":\"\"}")),
    ])
    func `each Body Type switch keeps what the new type can hold`(body: Body, type: BodyType, converted: Body) {
        #expect(BodyConversion.convert(body, to: type) == converted)
    }

    static let graphql = Body.graphql(GraphQLBody(query: "query Q { a }", variables: "{\"id\": 1}", operationName: "Q"))
    static let empty = Body.graphql(GraphQLBody(query: "", variables: "", operationName: ""))

    static func lifted(_ text: String) -> Body { .raw(.json, text) }

    @Test(arguments: [
        // a top-level object lifts all three; the variables are re-printed, order and spelling kept
        (#"{"query": "query Q { a }", "variables": {"b": 1.50, "a": [1,2]}, "operationName": "Q"}"#,
         GraphQLBody(query: "query Q { a }", variables: "{\n  \"b\": 1.50,\n  \"a\": [\n    1,\n    2\n  ]\n}", operationName: "Q")),
        (#"{"operationName":"Q","query":"{ a }"}"#, GraphQLBody(query: "{ a }", variables: "", operationName: "Q")),
        // escapes in the query are decoded
        (#"{"query":"{\n  a(x: \"y\")\n}"}"#, GraphQLBody(query: "{\n  a(x: \"y\")\n}", variables: "", operationName: "")),
        // a Variable is a value the way Format reads it
        (#"{"query":"{ a }","variables":{"id": {{id}}}}"#, GraphQLBody(query: "{ a }", variables: "{\n  \"id\": {{id}}\n}", operationName: "")),
        // variables may be any JSON value; null has nothing to lift
        (#"{"query":"{ a }","variables":null}"#, GraphQLBody(query: "{ a }", variables: "", operationName: "")),
        (#"{"query":"{ a }","variables":{}}"#, GraphQLBody(query: "{ a }", variables: "{}", operationName: "")),
        (#"{"query":"{ a }","variables":[1]}"#, GraphQLBody(query: "{ a }", variables: "[\n  1\n]", operationName: "")),
        // query and operationName are lifted only when strings
        (#"{"query":5,"operationName":null,"variables":{"a":1}}"#, GraphQLBody(query: "", variables: "{\n  \"a\": 1\n}", operationName: "")),
        (#"{"query":{"x":1},"operationName":["Q"]}"#, GraphQLBody(query: "", variables: "", operationName: "")),
        // other members are dropped, and the last of a repeated key wins
        (#"{"extensions":{"query":"no"},"query":"{ a }","query":"{ b }"}"#, GraphQLBody(query: "{ b }", variables: "", operationName: "")),
        // a Variable as a key starts a member of its own, and is dropped
        (#"{"query":"x",{{k}}: 1}"#, GraphQLBody(query: "x", variables: "", operationName: "")),
        (#"{"variables":{"a":1},{{k}}: {"b":[2]},"operationName":"Q"}"#,
         GraphQLBody(query: "", variables: "{\n  \"a\": 1\n}", operationName: "Q")),
        // non-ASCII text and \u escapes, a surrogate pair included, come out as characters
        (#"{"query":"😀 \u00e9 \ud83d\ude00"}"#, GraphQLBody(query: "😀 é 😀", variables: "", operationName: "")),
        (#"{"foo":1}"#, GraphQLBody(query: "", variables: "", operationName: "")),
        (#"{}"#, GraphQLBody(query: "", variables: "", operationName: "")),
    ])
    func `raw JSON lifts query, variables and operationName from a top-level object`(text: String, lifted: GraphQLBody) {
        #expect(BodyConversion.convert(Self.lifted(text), to: .graphql) == .graphql(lifted))
    }

    @Test(arguments: ["", "   ", "not json", #"{"query": "{ a }""#, #"{"query": }"#, "[1, 2]", #""query""#, "42", "null", "{{body}}", #"[{"query":"{ a }"}]"#])
    func `JSON that is invalid or not an object starts an empty GraphQL body`(text: String) {
        #expect(BodyConversion.convert(Self.lifted(text), to: .graphql) == Self.empty)
    }

    static let accept = Row(name: "Accept", value: "*/*")

    @Test(arguments: [
        ([accept], BodyType.none, BodyType.raw(.json), [accept, Row(name: "Content-Type", value: "application/json")]),
        ([Row(name: "content-type", value: "application/json"), accept], .raw(.json), .raw(.xml),
         [Row(name: "content-type", value: "application/xml"), accept]),
        ([Row(name: "Content-Type", value: "text/plain")], .raw(.text), .formURLEncoded,
         [Row(name: "Content-Type", value: "application/x-www-form-urlencoded")]),
        ([Row(name: "Content-Type", value: "application/x-www-form-urlencoded")], .formURLEncoded, .multipart,
         [Row(name: "Content-Type", value: "multipart/form-data")]),
        ([accept, Row(name: "Content-Type", value: "application/json")], .raw(.json), .none, [accept]),
        ([accept], .raw(.json), .none, [accept]),
    ])
    func `Content-Type follows the Body Type when the rule set it or none is set`(headers: [Row], from: BodyType, to: BodyType, result: [Row]) {
        #expect(Headers.contentType(headers, from: from, to: to) == result)
    }

    @Test(arguments: [
        [Row(name: "Content-Type", value: "application/vnd.api+json")],
        [Row(name: "Content-Type", value: "application/json", isEnabled: false)],
    ])
    func `a Content-Type the user set or disabled is never overwritten`(headers: [Row]) {
        #expect(Headers.contentType(headers, from: .raw(.json), to: .raw(.xml)) == headers)
        #expect(Headers.contentType(headers, from: .raw(.json), to: .none) == headers)
    }

    @Test(arguments: [
        ([accept], BodyType.none, [accept, Row(name: "Content-Type", value: "application/json")]),
        ([Row(name: "Content-Type", value: "text/plain")], .raw(.text), [Row(name: "Content-Type", value: "application/json")]),
        ([Row(name: "Content-Type", value: "application/json")], .raw(.json), [Row(name: "Content-Type", value: "application/json")]),
        ([Row(name: "Content-Type", value: "application/vnd.api+json")], .raw(.json), [Row(name: "Content-Type", value: "application/vnd.api+json")]),
        ([Row(name: "Content-Type", value: "application/json", isEnabled: false)], .raw(.json), [Row(name: "Content-Type", value: "application/json", isEnabled: false)]),
    ])
    func `picking GraphQL writes application/json and keeps a Content-Type the user set`(headers: [Row], from: BodyType, result: [Row]) {
        #expect(Headers.contentType(headers, from: from, to: .graphql) == result)
    }

    @Test func `a Body knows its Body Type`() {
        #expect([Body.none, Self.raw, Self.form, Self.multipart].map(\.type) == [.none, .raw(.json), .formURLEncoded, .multipart])
        #expect(Self.graphql.type == .graphql)
    }
}

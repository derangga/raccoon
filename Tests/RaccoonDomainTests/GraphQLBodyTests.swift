import Foundation
import RaccoonDomain
import Testing

struct GraphQLBodyTests {
    static let id = RequestID(UUID(uuidString: "6F1C2B3A-0000-4000-8000-000000000001")!)

    static func request(_ body: Body) -> Request {
        var definition = RequestDefinition.empty
        definition.method = "POST"
        definition.url = "https://api.example.com/graphql"
        definition.body = body
        return Request(id: id, name: "Query", definition: definition)
    }

    @Test(arguments: [
        GraphQLBody(query: "{ me { id } }", variables: "", operationName: ""),
        GraphQLBody(query: "query U($id: ID!) { user(id: $id) { id } }", variables: #"{"id": "1"}"#, operationName: ""),
        GraphQLBody(query: "query U($id: ID!) { user(id: $id) { id } }", variables: #"{"id": "1"}"#, operationName: "U"),
    ])
    func `a GraphQL body round-trips through a RequestFile`(body: GraphQLBody) throws {
        let request = Self.request(.graphql(body))
        #expect(try RequestFile.decode(RequestFile.encode(request)) == request)
    }

    @Test func `variables and operationName are left out of the file when empty`() throws {
        let text = String(decoding: RequestFile.encode(Self.request(.graphql(GraphQLBody(query: "{ a }", variables: "", operationName: "")))), as: UTF8.self)
        #expect(text.contains(#""type" : "graphql""#))
        #expect(text.contains(#""query" : "{ a }""#))
        #expect(!text.contains("variables"))
        #expect(!text.contains("operationName"))
    }

    @Test func `a GraphQL body with no query decodes as query empty`() throws {
        let json = #"{"version": 1, "id": "6F1C2B3A-0000-4000-8000-000000000001", "name": "Query", "method": "POST", "url": "x", "body": {"type": "graphql"}}"#
        let request = try RequestFile.decode(Data(json.utf8))
        #expect(request.definition.body == .graphql(GraphQLBody(query: "", variables: "", operationName: "")))
    }

    @Test func `Body.type reads graphql off a Body`() {
        #expect(Body.graphql(GraphQLBody(query: "", variables: "", operationName: "")).type == .graphql)
    }
}

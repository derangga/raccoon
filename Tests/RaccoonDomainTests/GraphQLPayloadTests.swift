import RaccoonDomain
import Testing

struct GraphQLPayloadTests {
    static let encoded: [(query: String, variables: String, operationName: String, payload: String)] = [
        // Variables and operationName empty (or only space) are left out.
        ("{ me { id } }", "", "", #"{"query":"{ me { id } }"}"#),
        ("{ me }", " \n ", "  ", #"{"query":"{ me }"}"#),
        // Keys in this order, no added whitespace, the object as typed but trimmed.
        ("query Q($id: ID!) { u(id: $id) { n } }", #"  {"id": 42}  "#, "Q",
         #"{"query":"query Q($id: ID!) { u(id: $id) { n } }","variables":{"id": 42},"operationName":"Q"}"#),
        ("{ me }", "{}", "", #"{"query":"{ me }","variables":{}}"#),
        // Escaping in the query and the operation name; a slash and non-ASCII text stay as they are.
        ("{ a(s: \"x\\y\") }\n\t{ b }", "", "O\"p",
         #"{"query":"{ a(s: \"x\\y\") }\n\t{ b }","operationName":"O\"p"}"#),
        ("{ a(u: \"/é\u{1}\") }", "", "", "{\"query\":\"{ a(u: \\\"/é\\u0001\\\") }\"}"),
        // \b, \f and \r are escaped; U+2028 is legal in a JSON string and stays as typed.
        ("a\u{8}b\u{c}c\rd\u{2028}e", "", "", "{\"query\":\"a\\bb\\fc\\rd\u{2028}e\"}"),
        // A `{{` inside a JSON string is valid JSON.
        ("{ me }", #"{"a": "{{x}}"}"#, "", #"{"query":"{ me }","variables":{"a": "{{x}}"}}"#),
    ]

    @Test(arguments: encoded)
    func `the payload is the query, the variables object and the operation name, in that order`(
        query: String, variables: String, operationName: String, payload: String
    ) throws {
        #expect(try GraphQLPayload.encode(query: query, variables: variables, operationName: operationName) == payload)
    }

    static let notObjects: [(variables: String, line: Int, column: Int)] = [
        ("[1]", 1, 1), ("3", 1, 1), (#""s""#, 1, 1), ("  \n  null", 2, 3), ("true", 1, 1),
        // Not JSON at all: the position the formatter reports.
        (#"{"a": }"#, 1, 7), ("{\n  \"a\": 1,\n}", 3, 1), ("{", 1, 2),
        // A `{{name}}` left unsubstituted is not an object either.
        ("{{id}}", 1, 1),
        // A name that is not a Variable survives substitution: `{{` outside a string is an error at its position.
        (#"{"id": {{user id}}}"#, 1, 8), (#"{{"a": 1}"#, 1, 1),
        // Trailing text after the object.
        (#"{"a":1} x"#, 1, 9),
    ]

    @Test(arguments: notObjects)
    func `Variables that are not a JSON object throw with a 1-based line and column`(variables: String, line: Int, column: Int) {
        #expect(throws: ResolveError.graphqlVariables(line: line, column: column)) {
            try GraphQLPayload.encode(query: "{ me }", variables: variables, operationName: "")
        }
    }

    @Test func `the text of a body is the same shape, and bad Variables are kept verbatim`() {
        let body = GraphQLBody(query: "{ me }", variables: #" {"id": {{id}}} "#, operationName: "Q")
        #expect(GraphQLPayload.text(body) == #"{"query":"{ me }","variables":{"id": {{id}}},"operationName":"Q"}"#)
        #expect(GraphQLPayload.text(GraphQLBody(query: "{ me }", variables: "[1,", operationName: "")) == #"{"query":"{ me }","variables":[1,}"#)
        #expect(GraphQLPayload.text(GraphQLBody(query: "", variables: "", operationName: "")) == #"{"query":""}"#)
    }
}

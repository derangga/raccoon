import Foundation
import RaccoonDomain
import Testing

struct CredentialScanTests {
    static func definition(
        headers: [Row] = [], params: [Row] = [], cookies: [Row] = [], auth: Auth = .none, body: Body = .none
    ) -> RequestDefinition {
        var definition = RequestDefinition.empty
        definition.headers = headers
        definition.params = params
        definition.cookies = cookies
        definition.auth = auth
        definition.body = body
        return definition
    }

    static func find(_ definition: RequestDefinition, name: String = "r") -> [CredentialFinding] {
        CredentialScan.find([Request(id: RequestID(UUID()), name: name, definition: definition)])
    }

    @Test func `Docs are never scanned`() {
        var definition = Self.definition()
        definition.docs = "Authorization: Bearer abc\ntoken=secret123 password: hunter2"
        #expect(Self.find(definition) == [])
    }

    @Test func `a finding is the Request's name and the place, in Request order, headers then params then Auth`() {
        let first = Request(id: RequestID(UUID()), name: "A", definition: Self.definition(
            headers: [Row(name: "Authorization", value: "x")], params: [Row(name: "token", value: "y")], auth: .bearer(token: "z")
        ))
        let clean = Request(id: RequestID(UUID()), name: "B", definition: .empty)
        let last = Request(id: RequestID(UUID()), name: "C", definition: Self.definition(auth: .basic(user: "u", password: "p")))
        #expect(CredentialScan.find([first, clean, last]) == [
            CredentialFinding(request: "A", place: .header("Authorization")),
            CredentialFinding(request: "A", place: .query("token")),
            CredentialFinding(request: "A", place: .bearerToken),
            CredentialFinding(request: "C", place: .basicPassword),
        ])
    }

    @Test(arguments: [
        ("authorization", true), ("Authorization", true), ("  AUTHORIZATION ", true), ("proxy-authorization", true),
        ("key", true), ("Key", true), ("X-Token", true), ("Access-Token", true), ("client_secret", true),
        ("Password", true), ("passwd", true), ("apikey", true), ("X-Api-Key", true), ("x_api_key", true),
        ("keys", false), ("monkey", false), ("Accept", false), ("Content-Type", false), ("", false),
    ])
    func `a header name is a credential name by the list`(name: String, found: Bool) {
        #expect(Self.find(Self.definition(headers: [Row(name: name, value: "abc")])).map(\.place)
            == (found ? [.header(name)] : []))
    }

    @Test(arguments: [
        ("token", true), ("access_token", true), ("api-key", true), ("key", true), ("authorization", true),
        ("proxy-authorization", true), ("secret", true), ("password", true),
        ("keys", false), ("monkey", false), ("page", false),
    ])
    func `a Params name is a credential name by the same list`(name: String, found: Bool) {
        #expect(Self.find(Self.definition(params: [Row(name: name, value: "abc")])).map(\.place)
            == (found ? [.query(name)] : []))
    }

    @Test(arguments: [
        ("{{bearer}}", false), ("Bearer {{token}}", false), ("{{ token }}", false), ("a{{b}}c", false),
        ("{{$guid}}", true), ("{{$token}}", true), ("{{not a name}}", true), ("{{", true),
        ("Bearer eyJ", true), ("abc", true),
    ])
    func `a value with a {{name}} is a reference and not found`(value: String, found: Bool) {
        let place: CredentialPlace = .header("authorization")
        #expect(Self.find(Self.definition(headers: [Row(name: "authorization", value: value)])).map(\.place) == (found ? [place] : []))
        #expect(Self.find(Self.definition(params: [Row(name: "token", value: value)])).count == (found ? 1 : 0))
        #expect(Self.find(Self.definition(auth: .bearer(token: value))).count == (found ? 1 : 0))
        #expect(Self.find(Self.definition(auth: .basic(user: "u", password: value))).count == (found ? 1 : 0))
    }

    @Test func `an empty Headers or Params value counts`() {
        #expect(Self.find(Self.definition(headers: [Row(name: "authorization", value: "")])).map(\.place) == [.header("authorization")])
        #expect(Self.find(Self.definition(params: [Row(name: "token", value: "")])).map(\.place) == [.query("token")])
    }

    @Test(arguments: ["", " ", "  \t\n"])
    func `an empty or whitespace Auth value is not a finding`(value: String) {
        #expect(Self.find(Self.definition(auth: .bearer(token: value))) == [])
        #expect(Self.find(Self.definition(auth: .basic(user: "u", password: value))) == [])
    }

    @Test func `a Disabled Row counts, because the file holds it`() {
        let found = Self.find(Self.definition(
            headers: [Row(name: "authorization", value: "abc", isEnabled: false)],
            params: [Row(name: "token", value: "abc", isEnabled: false)]
        ))
        #expect(found.map(\.place) == [.header("authorization"), .query("token")])
    }

    @Test func `a Disabled Row whose value is a reference is not found`() {
        let found = Self.find(Self.definition(
            headers: [Row(name: "authorization", value: "{{ref}}", isEnabled: false)],
            params: [Row(name: "token", value: "Bearer {{ref}}", isEnabled: false)]
        ))
        #expect(found == [])
    }

    @Test func `the Basic user name is not a credential, and Auth none is nothing`() {
        #expect(Self.find(Self.definition(auth: .basic(user: "admin", password: "{{pw}}"))) == [])
        #expect(Self.find(Self.definition(auth: .none)) == [])
    }

    @Test func `Cookie headers, Request Cookies and Body fields are not scanned`() {
        let found = Self.find(Self.definition(
            headers: [Row(name: "Cookie", value: "session=abc; token=def")],
            cookies: [Row(name: "token", value: "abc"), Row(name: "authorization", value: "abc")],
            body: .formURLEncoded([Row(name: "client_secret", value: "abc")])
        ))
        #expect(found == [])
    }

    @Test func `a Request with two credentials has two findings`() {
        #expect(Self.find(Self.definition(headers: [
            Row(name: "authorization", value: "a"), Row(name: "Access-Token", value: "b"),
        ]), name: "Two").map(\.request) == ["Two", "Two"])
    }

    @Test(.enabled(if: PostmanExporterTests.hasSample))
    func `the example Collection has 18 credentials in 18 Requests`() throws {
        let plan = PostmanExporterTests.plan(try Data(contentsOf: PostmanExporterTests.sample))
        func requests(_ nodes: [ImportNode]) -> [Request] {
            nodes.flatMap { node -> [Request] in
                switch node {
                case .request(let request): [request]
                case .folder(_, let children): requests(children)
                }
            }
        }
        let all = requests(try #require(plan.collections.first).nodes)
        #expect(all.count == 41)
        let found = CredentialScan.find(all)
        #expect(found.count == 18)
        #expect(Set(found.map(\.request)).count == 18)
        #expect(found.filter { $0.place == .header("authorization") }.count == 16)
        #expect(found.filter { $0.place == .header("Access-Token") }.count == 2)
    }
}

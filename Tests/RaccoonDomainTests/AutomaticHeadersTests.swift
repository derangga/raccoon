import RaccoonDomain
import Testing

struct AutomaticHeadersTests {
    func resolved(_ url: String, method: String = "GET", headers: [Row] = [], body: Body = .none) throws -> ResolvedRequest {
        var definition = RequestDefinition.empty
        definition.method = method
        definition.url = url
        definition.headers = headers
        definition.body = body
        return try VariableResolver.resolve(definition)
    }

    func header(_ name: String, _ value: String?) -> AutomaticHeader {
        AutomaticHeader(name: name, value: value)
    }

    var always: [AutomaticHeader] {
        [header("Accept", "*/*"), header("Accept-Language", "*"), header("Accept-Encoding", "gzip, deflate"),
         header("Connection", "keep-alive"), header("User-Agent", AutomaticHeaders.userAgent)]
    }

    @Test func `a GET with no rows shows every header URLSession adds, Host with its port`() throws {
        #expect(AutomaticHeaders.rows(for: try resolved("http://127.0.0.1:8080/x")) == [header("Host", "127.0.0.1:8080")] + always)
        #expect(AutomaticHeaders.rows(for: try resolved("http://example.com/")).first == header("Host", "example.com"))
    }

    @Test func `over https Accept-Encoding also offers br`() throws {
        #expect(AutomaticHeaders.rows(for: try resolved("https://example.com/")).contains(header("Accept-Encoding", "gzip, deflate, br")))
    }

    @Test(arguments: [
        (Body.raw(.json, "{}"), [Row](), [AutomaticHeader(name: "Content-Type", value: "application/x-www-form-urlencoded"), AutomaticHeader(name: "Content-Length", value: nil)]),
        (Body.formURLEncoded([Row(name: "a", value: "1")]), [], [AutomaticHeader(name: "Content-Type", value: "application/x-www-form-urlencoded"), AutomaticHeader(name: "Content-Length", value: nil)]),
        (Body.multipart([]), [], [AutomaticHeader(name: "Content-Type", value: "multipart/form-data"), AutomaticHeader(name: "Content-Length", value: nil)]),
        (Body.raw(.json, "{}"), [Row(name: "content-type", value: "application/json")], [AutomaticHeader(name: "Content-Length", value: nil)]),
    ])
    func `a body adds Content-Length, and Content-Type when no row sets one`(body: Body, headers: [Row], added: [AutomaticHeader]) throws {
        let rows = AutomaticHeaders.rows(for: try resolved("http://h/", method: "POST", headers: headers, body: body))
        #expect(Array(rows.dropFirst(6)) == added)
    }

    @Test(arguments: ["DELETE", "PUT", "PATCH"])
    func `only a POST body gets the form Content-Type, the other methods send Content-Length alone`(method: String) throws {
        for body in [Body.raw(.json, "{}"), .formURLEncoded([Row(name: "a", value: "1")])] {
            let rows = AutomaticHeaders.rows(for: try resolved("http://h/", method: method, body: body))
            #expect(Array(rows.dropFirst(6)) == [header("Content-Length", nil)])
        }
    }

    @Test func `a multipart body names its Content-Type on every method, the transport sets it`() throws {
        let rows = AutomaticHeaders.rows(for: try resolved("http://h/", method: "PUT", body: .multipart([])))
        #expect(Array(rows.dropFirst(6)) == [header("Content-Type", "multipart/form-data"), header("Content-Length", nil)])
    }

    @Test func `an enabled row replaces the automatic one, a Disabled Row does not`() throws {
        let headers = [Row(name: "user-agent", value: "curl/8"), Row(name: "Accept", value: "x", isEnabled: false), Row(name: "Host", value: "other")]
        let names = AutomaticHeaders.rows(for: try resolved("http://h/", headers: headers)).map(\.name)
        #expect(names == ["Accept", "Accept-Language", "Accept-Encoding", "Connection"])
    }
}

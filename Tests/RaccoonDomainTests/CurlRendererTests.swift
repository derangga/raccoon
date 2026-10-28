import RaccoonDomain
import Testing

struct CurlRendererTests {
    func render(
        _ method: String = "GET", _ url: String = "https://h/", params: [Row] = [], headers: [Row] = [], cookies: [Row] = [],
        body: Body = .none, auth: Auth = .none, insecure: Bool = false, redirects: Bool = false
    ) throws -> String {
        let definition = RequestDefinition(
            method: method, url: url, params: params, headers: headers, cookies: cookies, body: body, auth: auth,
            settings: RequestSettings(allowsInsecureTLS: insecure, followsRedirects: redirects)
        )
        return CurlRenderer.render(try VariableResolver.resolve(definition))
    }

    @Test func `a Path Variable's value is in the URL, an empty one is :id, and a secret kept as written stays {{key}}`() throws {
        var request = RequestDefinition.empty
        request.url = "https://h/posts/:id/x/:other/:key"
        request.pathVariables = ["id": "a b", "key": "{{key}}"]
        let scope = VariableScope(values: [VariableName("key")!: "{{key}}"])
        #expect(CurlRenderer.render(try VariableResolver.resolve(request, scope: scope)) == "curl 'https://h/posts/a%20b/x/:other/{{key}}'")
    }

    @Test func `a GET with no body is the URL alone`() throws {
        #expect(try render() == "curl 'https://h/'")
    }

    @Test func `an enabled Authorization row and Auth write one Authorization header`() throws {
        #expect(try render(headers: [Row(name: "Authorization", value: "Basic eHl6")], auth: .bearer(token: "abc"))
            == "curl 'https://h/' \\\n  -H 'Authorization: Basic eHl6'")
    }

    @Test func `the refund POST renders flag by flag`() throws {
        let text = try render(
            "POST", "https://api.example.com/v1/refunds",
            headers: [Row(name: "Content-Type", value: "application/json")],
            cookies: [Row(name: "session", value: "7f3a"), Row(name: "locale", value: "en")],
            body: .raw(.json, #"{"charge":"ch_3PqL8x2e","amount":500}"#),
            auth: .bearer(token: "t0k")
        )
        #expect(text == #"""
            curl -X POST 'https://api.example.com/v1/refunds' \
              -H 'Content-Type: application/json' \
              -H 'Authorization: Bearer t0k' \
              -b 'session=7f3a; locale=en' \
              --data-raw '{"charge":"ch_3PqL8x2e","amount":500}'
            """#)
    }

    @Test(arguments: [
        (Body.raw(.text, "it's"), #"--data-raw 'it'\''s'"#),
        (.formURLEncoded([Row(name: "q", value: "a b&c")]), "--data-urlencode 'q=a b&c'"),
        (.multipart([Part(name: "a", content: .text("1")), Part(name: "f", content: .file(path: "/tmp/o'k.png"))]),
         #"-F 'a=1' \"# + "\n  " + #"-F 'f=@/tmp/o'\''k.png'"#),
    ])
    func `each Body Type has its flag, and a single quote is escaped`(body: Body, flags: String) throws {
        #expect(try render("POST", body: body) == "curl -X POST 'https://h/' \\\n  " + flags)
    }

    @Test(arguments: [
        (Auth.basic(user: "user", password: "pass"), "Basic dXNlcjpwYXNz"),
        (.bearer(token: "abc.def"), "Bearer abc.def"),
    ])
    func `Auth arrives as an Authorization header`(auth: Auth, value: String) throws {
        #expect(try render(auth: auth) == "curl 'https://h/' \\\n  -H 'Authorization: \(value)'")
    }

    @Test func `settings are -k and -L, and an empty header is Name;`() throws {
        #expect(try render(headers: [Row(name: "X-Empty", value: "")], insecure: true, redirects: true)
            == "curl 'https://h/' \\\n  -H 'X-Empty;' \\\n  -k \\\n  -L")
    }

    @Test func `a GET with a body says -X, and an odd method is quoted`() throws {
        #expect(try render("GET", body: .raw(.text, "x")) == "curl -X GET 'https://h/' \\\n  --data-raw 'x'")
        #expect(try render("M-SEARCH") == "curl -X 'M-SEARCH' 'https://h/'")
    }

    @Test func `Disabled Rows never appear`() throws {
        let text = try render(
            params: [Row(name: "on", value: "1"), Row(name: "off", value: "2", isEnabled: false)],
            headers: [Row(name: "X-Off", value: "1", isEnabled: false)],
            cookies: [Row(name: "c", value: "1", isEnabled: false)]
        )
        #expect(text == "curl 'https://h/?on=1'")
    }
}

/// The Curl pane's states (curl.md §The Curl pane): a command, or why there is none.
struct CurlPreviewTests {
    let host = VariableName("host")!
    let id = VariableName("charge_id")!

    func preview(_ url: String, headers: [Row] = [], values: [VariableName: String] = [:]) -> CurlPreview {
        CurlPreview(RequestDefinition(method: "GET", url: url, params: [], headers: headers, cookies: [], body: .none, auth: .none,
                                      settings: RequestSettings(allowsInsecureTLS: false, followsRedirects: false)), scope: VariableScope(values: values))
    }

    @Test func `a URL that resolves is the command Copy as Curl renders`() {
        #expect(preview("{{host}}/a", values: [host: "https://h"]) == .command("curl 'https://h/a'"))
    }

    @Test(arguments: ["", "   "])
    func `a blank URL asks for one, whatever else is undefined`(url: String) {
        #expect(preview(url, headers: [Row(name: "X", value: "{{charge_id}}")]) == .noURL)
    }

    @Test func `undefined names come in the order the request uses them`() {
        #expect(preview("{{host}}/{{charge_id}}") == .undefined([host, id]))
    }

    @Test func `a URL that is not one after substitution is quoted`() {
        #expect(preview("{{host}}/a", values: [host: "localhost:4000"]) == .invalidURL("localhost:4000/a"))
    }
}

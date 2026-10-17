import RaccoonDomain
import Testing

struct CurlMappingTests {
    func row(_ name: String, _ value: String) -> Row {
        Row(name: name, value: value)
    }

    @Test(arguments: ["curl", "curl -k -H 'a: b'", "curl --url ''"])
    func `a command with no URL is an error`(text: String) {
        #expect(throws: CurlImportError.noURL) { try CurlImporter.import(text) }
    }

    @Test func `a whole command maps to one definition`() throws {
        let imported = try CurlImporter.import("""
            curl -X put --retry 3 'https://h/search?q=a%20b&token=abc==' --url-query 'page=2' \\
              -H 'Accept: application/json' -H 'X-Empty;' -H 'Authorization: Bearer t0k' \\
              -k -L
            curl https://other/
            """)
        #expect(imported == CurlImport(
            definition: RequestDefinition(
                method: "PUT", url: "https://h/search",
                params: [row("q", "a b"), row("token", "abc=="), row("page", "2")],
                headers: [row("Accept", "application/json"), row("X-Empty", "")],
                cookies: [], body: .none, auth: .bearer(token: "t0k"),
                settings: RequestSettings(allowsInsecureTLS: true, followsRedirects: true)
            ),
            ignoredFlags: ["--retry"], fileReferences: [], skippedCommands: 1
        ))
    }

    @Test func `the URL is --url before the first positional, and the method defaults to GET`() throws {
        let definition = try CurlImporter.import("curl http://positional/ --url http://flag/ -XPATCH").definition
        #expect(definition.url == "http://flag/")
        #expect(definition.method == "PATCH")
        #expect(try CurlImporter.import("curl http://h/").definition.method == "GET")
    }

    @Test func `-b and a Cookie header become Request Cookies rows`() throws {
        let definition = try CurlImporter.import("curl http://h/ -b 'a=1; b=2' -H 'cookie: c=3' -H 'X: y'").definition
        #expect(definition.cookies == [row("a", "1"), row("b", "2"), row("c", "3")])
        #expect(definition.headers == [row("X", "y")])
    }

    @Test func `-b with a file name is ignored, because curl reads cookies from that file`() throws {
        let imported = try CurlImporter.import("curl http://h/ -b cookies.txt")
        #expect(imported.definition.cookies.isEmpty)
        #expect(imported.ignoredFlags == ["--cookie"])
    }

    @Test(arguments: [
        ("Authorization: Basic dXNlcjpwYXNz", Auth.basic(user: "user", password: "pass"), [Row]()),
        ("authorization: bearer abc.def", Auth.bearer(token: "abc.def"), []),
        ("Authorization: Basic bm90LWEtcGFpcg==", Auth.none, [Row(name: "Authorization", value: "Basic bm90LWEtcGFpcg==")]),
        ("Authorization: Basic !!!", Auth.none, [Row(name: "Authorization", value: "Basic !!!")]),
        ("Authorization: Digest x", Auth.none, [Row(name: "Authorization", value: "Digest x")]),
    ])
    func `an Authorization header becomes Auth only when it is Bearer or a user:pass Basic`(header: String, auth: Auth, headers: [Row]) throws {
        let definition = try CurlImporter.import("curl http://h/ -H '\(header)' -u other:one").definition
        #expect(definition.auth == auth)
        #expect(definition.headers == headers)
    }

    @Test(arguments: [
        ("-u a:b", Auth.basic(user: "a", password: "b"), [String]()),
        ("-u a:b:c --digest", Auth.basic(user: "a", password: "b:c"), ["--digest"]),
        ("--user a", Auth.basic(user: "a", password: ""), []),
    ])
    func `-u is Basic, even with --digest, which is ignored`(flags: String, auth: Auth, ignored: [String]) throws {
        let imported = try CurlImporter.import("curl http://h/ \(flags)")
        #expect(imported.definition.auth == auth)
        #expect(imported.ignoredFlags == ignored)
    }

    @Test func `--compressed sets nothing and is ignored`() throws {
        let imported = try CurlImporter.import("curl http://h/ --compressed")
        #expect(imported.definition == RequestDefinition(
            method: "GET", url: "http://h/", params: [], headers: [], cookies: [], body: .none, auth: .none,
            settings: RequestSettings(allowsInsecureTLS: false, followsRedirects: false)
        ))
        #expect(imported.ignoredFlags == ["--compressed"])
    }

    @Test(arguments: [
        ("echo.usebruno.com/a?b=1", "http://echo.usebruno.com/a"),
        ("https://h/", "https://h/"),
        ("ftp://h/", "ftp://h/"),
    ])
    func `a URL with no scheme gets http://, as curl sends it`(text: String, url: String) throws {
        #expect(try CurlImporter.import("curl \(text)").definition.url == url)
    }

    @Test func `-I is HEAD unless -X says otherwise`() throws {
        #expect(try CurlImporter.import("curl -I http://h/").definition.method == "HEAD")
        #expect(try CurlImporter.import("curl --head -X GET http://h/").definition.method == "GET")
    }

    @Test func `-A is a User-Agent header in command order`() throws {
        let definition = try CurlImporter.import("curl -H 'X: 1' -A 'Custom Agent' --user-agent Two http://h/").definition
        #expect(definition.headers == [row("X", "1"), row("User-Agent", "Custom Agent"), row("User-Agent", "Two")])
    }

    @Test func `a cookie part with no = is dropped`() throws {
        let definition = try CurlImporter.import("curl http://h/ -b 'a=1; path=/; secure; HttpOnly'").definition
        #expect(definition.cookies == [row("a", "1"), row("path", "/")])
    }
}

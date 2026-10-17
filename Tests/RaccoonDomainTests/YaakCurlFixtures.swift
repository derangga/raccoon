// The inputs below are copied from Yaak's curl importer tests,
// yaak/plugins/importer-curl/tests/index.test.ts, and each case is named after its Yaak test.
// The expected outputs are rewritten as Raccoon's CurlImport; where Raccoon differs on purpose,
// the comment names the rule in design/entry-points/curl.md.
//
// MIT License
//
// Copyright (c) 2024 Yaak
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in all
// copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.

import RaccoonDomain
import Testing

enum YaakCurlFixtures {
    static let all: [CurlFixture] = [
        CurlFixture("Imports basic GET", "curl https://yaak.app", request("https://yaak.app")),
        // Differs: -L sets Follow redirects ("-L sets Follow redirects"); -f, -s and -S are
        // listed for the Ignored note.
        CurlFixture("Imports combined short flags", "curl -fsSL https://yaak.app",
                    request("https://yaak.app", redirects: true, ignored: ["-f", "-s", "-S"])),
        CurlFixture("Imports a combined short cluster ending in a value flag", "curl -sSXPOST https://yaak.app",
                    request("https://yaak.app", method: "POST", ignored: ["-s", "-S"])),
        CurlFixture("Explicit URL", "curl --url https://yaak.app", request("https://yaak.app")),
        // Differs: no URL is the noURL error (the url node's E: noURL), not a request with none.
        CurlFixture("Missing URL", "curl -X POST", throws: .noURL),
        CurlFixture("URL between", "curl -v https://yaak.app -X POST",
                    request("https://yaak.app", method: "POST", ignored: ["-v"])),
        // -Y takes a value, so it consumes -S, as curl does.
        CurlFixture("Random flags", "curl --random -Z -Y -S --foo https://yaak.app",
                    request("https://yaak.app", ignored: ["--random", "-Z", "-Y", "--foo"])),
        CurlFixture("Imports --request method", "curl --request POST https://yaak.app",
                    request("https://yaak.app", method: "POST")),
        CurlFixture("Imports -XPOST method", "curl -XPOST --request POST https://yaak.app",
                    request("https://yaak.app", method: "POST")),
        // Differs: only the first command is imported ("Several pasted commands import only the
        // first"); echo is not a curl command, so two are skipped.
        CurlFixture("Imports multiple requests", "curl \\\n  https://yaak.app\necho \"foo\"\ncurl example.com;curl foo.com",
                    request("https://yaak.app", skipped: 2)),
        CurlFixture("Imports line continuations with trailing whitespace after the backslash",
                    "curl -X POST https://yaak.app \\ \n  -H 'Content-Type: application/json' \\\t\n  --data '{\"a\":1}' \\ \r\n  -H 'Accept: application/json'",
                    request("https://yaak.app", method: "POST",
                            headers: rows(("Content-Type", "application/json"), ("Accept", "application/json")),
                            body: .raw(.json, #"{"a":1}"#))),
        CurlFixture("Imports with Windows CRLF line endings", "curl \\\r\n  -X POST \\\r\n  https://yaak.app",
                    request("https://yaak.app", method: "POST")),
        CurlFixture("Throws on malformed quotes", #"curl -X POST -F "a=aaa" -F b=bbb" https://yaak.app"#,
                    throws: .unterminatedQuote(position: 33)),
        // Differs: no Content-Type row ("No Content-Type row is added").
        CurlFixture("Imports form data", #"curl -X POST -F "a=aaa" -F b=bbb -F f=@filepath https://yaak.app"#,
                    request("https://yaak.app", method: "POST",
                            body: parts(("a", .text("aaa")), ("b", .text("bbb")), ("f", .file(path: "filepath"))))),
        // Differs: no Content-Type row ("No Content-Type row is added"), here and in every form
        // case below.
        CurlFixture("Imports data params as form url-encoded", "curl -d a -d b -d c=ccc https://yaak.app",
                    request("https://yaak.app", method: "POST", body: .formURLEncoded(rows(("a", ""), ("b", ""), ("c", "ccc"))))),
        CurlFixture("Imports combined data params as form url-encoded", "curl -d 'a=aaa&b=bbb&c' https://yaak.app",
                    request("https://yaak.app", method: "POST", body: .formURLEncoded(rows(("a", "aaa"), ("b", "bbb"), ("c", ""))))),
        CurlFixture("Keeps an --data-urlencode value whole", "curl --data-urlencode 'q=a&b=c' https://yaak.app",
                    request("https://yaak.app", method: "POST", body: .formURLEncoded(rows(("q", "a&b=c"))))),
        CurlFixture("Imports a data value that is not valid percent-encoding", "curl -d 'a=100%' https://yaak.app",
                    request("https://yaak.app", method: "POST", body: .formURLEncoded(rows(("a", "100%"))))),
        CurlFixture("Keeps a valid escape decoded when the value also holds a stray percent",
                    "curl -d 'a=50%25 and 100%' https://yaak.app",
                    request("https://yaak.app", method: "POST", body: .formURLEncoded(rows(("a", "50% and 100%"))))),
        CurlFixture("Decodes -G --data-urlencode into the query string", "curl -G --data-urlencode 'q=a&b' https://yaak.app",
                    request("https://yaak.app", params: rows(("q", "a&b")))),
        CurlFixture("Imports data params as text", "curl -H Content-Type:text/plain -d a -d b -d c=ccc https://yaak.app",
                    request("https://yaak.app", method: "POST", headers: rows(("Content-Type", "text/plain")),
                            body: .raw(.text, "a&b&c=ccc"))),
        CurlFixture("Imports post data into URL", "curl -G https://api.stripe.com/v1/payment_links -d limit=3",
                    request("https://api.stripe.com/v1/payment_links", params: rows(("limit", "3")))),
        CurlFixture("Imports multi-line JSON", "curl -H Content-Type:application/json -d $'{\n  \"foo\":\"bar\"\n}' https://yaak.app",
                    request("https://yaak.app", method: "POST", headers: rows(("Content-Type", "application/json")),
                            body: .raw(.json, "{\n  \"foo\":\"bar\"\n}"))),
        // Differs: command order across -H and --header ("Headers keep command order").
        CurlFixture("Imports multiple headers", "curl -H Foo:bar --header Name -H AAA:bbb -H :ccc https://yaak.app",
                    request("https://yaak.app", headers: rows(("Foo", "bar"), ("Name", ""), ("AAA", "bbb"), ("", "ccc")))),
        CurlFixture("Imports basic auth", "curl --user user:pass https://yaak.app",
                    request("https://yaak.app", auth: .basic(user: "user", password: "pass"))),
        // Differs: Basic, with --digest ignored ("--digest and --ntlm are ignored, not mapped").
        CurlFixture("Imports digest auth", "curl --digest --user user:pass https://yaak.app",
                    request("https://yaak.app", auth: .basic(user: "user", password: "pass"), ignored: ["--digest"])),
        CurlFixture("Imports Bearer token from Authorization header", #"curl -H "Authorization: Bearer token123" https://yaak.app"#,
                    request("https://yaak.app", auth: .bearer(token: "token123"))),
        CurlFixture("Trims whitespace before Bearer token from Authorization header",
                    #"curl -H "Authorization: Bearer    token123" https://yaak.app"#,
                    request("https://yaak.app", auth: .bearer(token: "token123"))),
        CurlFixture("Imports Basic auth from Authorization header (base64 decoded)",
                    #"curl -H "Authorization: Basic dXNlcjpwYXNzd29yZA==" https://yaak.app"#,
                    request("https://yaak.app", auth: .basic(user: "user", password: "password"))),
        CurlFixture("Authorization header takes precedence over -u flag",
                    #"curl -u admin:secret -H "Authorization: Bearer token123" https://yaak.app"#,
                    request("https://yaak.app", auth: .bearer(token: "token123"))),
        CurlFixture("Authorization header extraction is case-insensitive",
                    #"curl -H "authorization: bearer lowercaseToken" https://yaak.app"#,
                    request("https://yaak.app", auth: .bearer(token: "lowercaseToken"))),
        CurlFixture("Preserves other headers when extracting Authorization",
                    #"curl -H "Authorization: Bearer token123" -H "X-Custom: value" https://yaak.app"#,
                    request("https://yaak.app", headers: rows(("X-Custom", "value")), auth: .bearer(token: "token123"))),
        CurlFixture("Invalid base64 in Basic auth keeps header in headers",
                    #"curl -H "Authorization: Basic not-valid-base64!!!" https://yaak.app"#,
                    request("https://yaak.app", headers: rows(("Authorization", "Basic not-valid-base64!!!")))),
        // Differs: a Request Cookies row, not a Cookie header ("Cookies become Request Cookies rows").
        CurlFixture("Imports cookie as header", #"curl --cookie "foo=bar" https://yaak.app"#,
                    request("https://yaak.app", cookies: rows(("foo", "bar")))),
        CurlFixture("Imports query params", #"curl "https://yaak.app" --url-query foo=bar --url-query baz=qux"#,
                    request("https://yaak.app", params: rows(("foo", "bar"), ("baz", "qux")))),
        CurlFixture("Imports query params from the URL", #"curl "https://yaak.app?foo=bar&baz=a%20a""#,
                    request("https://yaak.app", params: rows(("foo", "bar"), ("baz", "a a")))),
        // Differs: raw text, not form rows ("--data-raw and --data-binary with no Content-Type are
        // raw text").
        CurlFixture("Imports weird body", "curl 'https://yaak.app' -X POST --data-raw 'foo=bar=baz'",
                    request("https://yaak.app", method: "POST", body: .raw(.text, "foo=bar=baz"))),
        CurlFixture("Imports data with Unicode escape sequences",
                    #"curl 'https://yaak.app' -H 'Content-Type: application/json' --data-raw $'{"query":"SearchQueryInput\u0021"}' -X POST"#,
                    request("https://yaak.app", method: "POST", headers: rows(("Content-Type", "application/json")),
                            body: .raw(.json, #"{"query":"SearchQueryInput!"}"#))),
        // Differs: raw JSON, not a GraphQL body ("No GraphQL detection").
        CurlFixture("Imports GraphQL JSON data as a GraphQL request",
                    #"curl 'https://yaak.app/graphql' -H 'Content-Type: application/json' --data-raw $'{"query":"query Search($id: ID\u0021) { node(id: $id) { id } }","variables":{"id":"123"}}'"#,
                    request("https://yaak.app/graphql", method: "POST", headers: rows(("Content-Type", "application/json")),
                            body: .raw(.json, #"{"query":"query Search($id: ID!) { node(id: $id) { id } }","variables":{"id":"123"}}"#))),
        CurlFixture("Imports GraphQL JSON with extensions as JSON",
                    #"curl 'https://yaak.app/graphql' -H 'Content-Type: application/json' --data-raw $'{"query":"query Search($id: ID\u0021) { node(id: $id) { id } }","extensions":{"persistedQuery":{"version":1,"sha256Hash":"abc123"}}}'"#,
                    request("https://yaak.app/graphql", method: "POST", headers: rows(("Content-Type", "application/json")),
                            body: .raw(.json, #"{"query":"query Search($id: ID!) { node(id: $id) { id } }","extensions":{"persistedQuery":{"version":1,"sha256Hash":"abc123"}}}"#))),
        // Differs: raw text, not form rows ("--data-raw and --data-binary with no Content-Type are
        // raw text").
        CurlFixture("Imports data with multiple escape sequences",
                    #"curl 'https://yaak.app' --data-raw $'Line1\nLine2\tTab\u0021Exclamation' -X POST"#,
                    request("https://yaak.app", method: "POST", body: .raw(.text, "Line1\nLine2\tTab!Exclamation"))),
        CurlFixture("Imports multipart form data from --data-raw (Chrome DevTools format)", """
            curl 'http://localhost:8080/system' \\
              -H 'Content-Type: multipart/form-data; boundary=----WebKitFormBoundaryHwsXKi4rKA6P5VBd' \\
              --data-raw $'------WebKitFormBoundaryHwsXKi4rKA6P5VBd\\r\\nContent-Disposition: form-data; name="username"\\r\\n\\r\\njsgj\\r\\n------WebKitFormBoundaryHwsXKi4rKA6P5VBd\\r\\nContent-Disposition: form-data; name="password"\\r\\n\\r\\n654321\\r\\n------WebKitFormBoundaryHwsXKi4rKA6P5VBd\\r\\nContent-Disposition: form-data; name="captcha"; filename="test.xlsx"\\r\\nContent-Type: application/vnd.openxmlformats-officedocument.spreadsheetml.sheet\\r\\n\\r\\n\\r\\n------WebKitFormBoundaryHwsXKi4rKA6P5VBd--\\r\\n'
            """,
                    request("http://localhost:8080/system", method: "POST",
                            headers: rows(("Content-Type", "multipart/form-data; boundary=----WebKitFormBoundaryHwsXKi4rKA6P5VBd")),
                            body: parts(("username", .text("jsgj")), ("password", .text("654321")), ("captcha", .file(path: "test.xlsx"))))),
        CurlFixture("Imports JSON body with newlines in $quotes",
                    #"curl 'https://yaak.app' -H 'Content-Type: application/json' --data-raw $'{\n  "foo": "bar",\n  "baz": "qux"\n}' -X POST"#,
                    request("https://yaak.app", method: "POST", headers: rows(("Content-Type", "application/json")),
                            body: .raw(.json, "{\n  \"foo\": \"bar\",\n  \"baz\": \"qux\"\n}"))),
        // Differs: only the first command ("Several pasted commands import only the first").
        CurlFixture("Handles double-quoted string ending with even backslashes before semicolon",
                    #"curl -d "C:\\" https://yaak.app;curl https://example.com"#,
                    request("https://yaak.app", method: "POST", body: .formURLEncoded(rows(("C:\\", ""))), skipped: 1)),
        // Differs: only the first command ("Several pasted commands import only the first").
        CurlFixture("Handles $quoted string ending with a literal backslash before semicolon",
                    #"curl -d $'C:\\' https://yaak.app;curl https://example.com"#,
                    request("https://yaak.app", method: "POST", body: .formURLEncoded(rows(("C:\\", ""))), skipped: 1)),
        CurlFixture("Imports $quoted header with escaped single quotes", #"curl https://yaak.app -H $'X-Custom: it\'s a test'"#,
                    request("https://yaak.app", headers: rows(("X-Custom", "it's a test")))),
        CurlFixture("Does not split on escaped semicolon outside quotes", #"curl https://yaak.app?a=1\;b=2"#,
                    request("https://yaak.app", params: rows(("a", "1;b=2")))),
        CurlFixture("Imports multipart form data with text-only fields from --data-raw", """
            curl 'http://example.com/api' \\
              -H 'Content-Type: multipart/form-data; boundary=----FormBoundary123' \\
              --data-raw $'------FormBoundary123\\r\\nContent-Disposition: form-data; name="field1"\\r\\n\\r\\nvalue1\\r\\n------FormBoundary123\\r\\nContent-Disposition: form-data; name="field2"\\r\\n\\r\\nvalue2\\r\\n------FormBoundary123--\\r\\n'
            """,
                    request("http://example.com/api", method: "POST",
                            headers: rows(("Content-Type", "multipart/form-data; boundary=----FormBoundary123")),
                            body: parts(("field1", .text("value1")), ("field2", .text("value2"))))),
        CurlFixture("Keeps an = inside a --url-query value",
                    #"curl --url-query "filter=type=book" --url-query "t=eyJhIjoxfQ==" https://yaak.app"#,
                    request("https://yaak.app", params: rows(("filter", "type=book"), ("t", "eyJhIjoxfQ==")))),
        CurlFixture("Keeps an = inside a form value", #"curl -F "t=eyJhIjoxfQ==" -F "q=a=b" https://yaak.app"#,
                    request("https://yaak.app", method: "POST", body: parts(("t", .text("eyJhIjoxfQ==")), ("q", .text("a=b"))))),
        // Yaak checks its import holds nothing but the request; here, nothing but the definition.
        CurlFixture("Emits no source keys", "curl https://yaak.app", request("https://yaak.app")),
    ]
}

struct YaakCurlFixtureTests {
    @Test func `every Yaak test is ported`() {
        #expect(YaakCurlFixtures.all.count == 51)
    }

    @Test(arguments: YaakCurlFixtures.all)
    func `Yaak's curl fixtures import as Raccoon expects`(fixture: CurlFixture) {
        #expect(Result { () throws(CurlImportError) in try CurlImporter.import(fixture.input) } == fixture.expected)
    }
}

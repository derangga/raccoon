// The inputs below are copied from Bruno's curl parser tests,
// bruno/packages/bruno-app/src/utils/curl/parse-curl.spec.js, and each case is named after its
// Bruno test. Bruno writes them as JS template literals, so each input here is the string its
// parser received: a `\` + newline is already joined, `\\'` is already `\'`, and the template's
// surrounding blank lines are trimmed. The expected outputs are rewritten as Raccoon's
// CurlImport; where Raccoon differs on purpose, the comment names the rule in
// design/entry-points/curl.md.
//
// MIT License
//
// Copyright (c) 2022 Anoop M D, Anusree P S and Contributors
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

private let json = rows(("Content-Type", "application/json"))
private let jsonFlagHeaders = rows(("Content-Type", "application/json"), ("Accept", "application/json"))

enum BrunoCurlFixtures {
    static let all: [CurlFixture] = [
        CurlFixture("should parse simple GET request", "curl https://api.example.com/users",
                    request("https://api.example.com/users")),
        CurlFixture("should parse explicit POST method", "curl -X POST https://api.example.com/users",
                    request("https://api.example.com/users", method: "POST")),
        CurlFixture("should parse PUT method", "curl -X PUT https://api.example.com/users/1",
                    request("https://api.example.com/users/1", method: "PUT")),
        CurlFixture("should parse DELETE method", "curl -X DELETE https://api.example.com/users/1",
                    request("https://api.example.com/users/1", method: "DELETE")),
        CurlFixture("should parse HEAD method", "curl -I https://api.example.com/users",
                    request("https://api.example.com/users", method: "HEAD")),
        CurlFixture("should parse single header", #"curl --header "Content-Type: application/json" https://api.example.com"#,
                    request("https://api.example.com", headers: json)),
        CurlFixture("should parse single header (no space in header value)",
                    #"curl --header "Content-Type:application/json" https://api.example.com"#,
                    request("https://api.example.com", headers: json)),
        // Differs: the Bearer header becomes Auth (the auth node: Authorization: Bearer x -> .bearer).
        CurlFixture("should parse multiple headers",
                    #"curl -H "Content-Type: application/json"              -H "Authorization: Bearer token"              https://api.example.com"#,
                    request("https://api.example.com", headers: json, auth: .bearer(token: "token"))),
        CurlFixture("should parse user-agent header", #"curl -A "Custom User Agent" https://api.example.com"#,
                    request("https://api.example.com", headers: rows(("User-Agent", "Custom User Agent")))),
        // Differs: -d with no Content-Type is form-urlencoded (the body table), so the JSON is one
        // field name with no value; curl sends it with the form Content-Type too.
        CurlFixture("should parse JSON data and change method to POST",
                    #"curl -d '{"name": "John", "age": 30}' https://api.example.com/users"#,
                    request("https://api.example.com/users", method: "POST", body: .formURLEncoded(rows((#"{"name": "John", "age": 30}"#, ""))))),
        CurlFixture("should parse post data", #"curl --data "name=John&age=30" https://api.example.com/users"#,
                    request("https://api.example.com/users", method: "POST", body: .formURLEncoded(rows(("name", "John"), ("age", "30"))))),
        CurlFixture("should handle multiple data flags", #"curl -d "name=John"              -d "age=30"              https://api.example.com/users"#,
                    request("https://api.example.com/users", method: "POST", body: .formURLEncoded(rows(("name", "John"), ("age", "30"))))),
        // Differs: form-urlencoded, as above.
        CurlFixture("should keep multiline data", """
            curl -d '{"key": "some long message with line breaks


                         multiline"}'              https://api.example.com/users
            """,
                    request("https://api.example.com/users", method: "POST",
                            body: .formURLEncoded(rows(("{\"key\": \"some long message with line breaks\n\n\n             multiline\"}", ""))))),
        // Differs: form-urlencoded, as above.
        CurlFixture("should keep multi space data", #"curl -d '{"key": "some long    spaced     message"}'              https://api.example.com/users"#,
                    request("https://api.example.com/users", method: "POST",
                            body: .formURLEncoded(rows((#"{"key": "some long    spaced     message"}"#, ""))))),
        CurlFixture("should parse binary data flag", #"curl --data-binary "@/path/to/file" https://api.example.com/upload"#,
                    request("https://api.example.com/upload", method: "POST", body: .raw(.text, ""), files: ["/path/to/file"])),
        CurlFixture("should keep inline binary data as the body (not an @file reference)",
                    #"curl --data-binary '{"pageUri": "/mobile-phones-store"}' https://api.example.com/page/fetch"#,
                    request("https://api.example.com/page/fetch", method: "POST", body: .raw(.text, #"{"pageUri": "/mobile-phones-store"}"#))),
        CurlFixture("should parse raw data flag", #"curl --data-raw '{"raw": "data"}' https://api.example.com"#,
                    request("https://api.example.com", method: "POST", body: .raw(.text, #"{"raw": "data"}"#))),
        CurlFixture("should parse basic authentication", #"curl -u "username:password" https://api.example.com"#,
                    request("https://api.example.com", auth: .basic(user: "username", password: "password"))),
        CurlFixture("should handle username without password", #"curl --user "username" https://api.example.com"#,
                    request("https://api.example.com", auth: .basic(user: "username", password: ""))),
        // Differs: Basic, with the flag ignored ("--digest and --ntlm are ignored, not mapped"),
        // here and in the next four cases.
        CurlFixture("should parse digest authentication", #"curl --digest -u "myuser:mypass" https://api.example.com/digest"#,
                    request("https://api.example.com/digest", auth: .basic(user: "myuser", password: "mypass"), ignored: ["--digest"])),
        CurlFixture("should parse digest authentication with --user flag",
                    #"curl --digest --user "admin:secret" https://api.example.com/secure"#,
                    request("https://api.example.com/secure", auth: .basic(user: "admin", password: "secret"), ignored: ["--digest"])),
        CurlFixture("should parse NTLM authentication", #"curl --ntlm -u "myuser:mypass" https://api.example.com/ntlm"#,
                    request("https://api.example.com/ntlm", auth: .basic(user: "myuser", password: "mypass"), ignored: ["--ntlm"])),
        CurlFixture("should parse NTLM authentication with --user flag",
                    #"curl --ntlm --user "domain\username:password" https://api.example.com/ntlm"#,
                    request("https://api.example.com/ntlm", auth: .basic(user: #"domain\username"#, password: "password"), ignored: ["--ntlm"])),
        CurlFixture("should handle digest auth flag before -u flag", #"curl -u "user:pass" --digest https://api.example.com"#,
                    request("https://api.example.com", auth: .basic(user: "user", password: "pass"), ignored: ["--digest"])),
        CurlFixture("should parse form data with text fields", #"curl -F "name=John"              -F "age=30"              https://api.example.com/users"#,
                    request("https://api.example.com/users", method: "POST", body: parts(("name", .text("John")), ("age", .text("30"))))),
        CurlFixture("should parse form data with file uploads", #"curl --form "file=@/path/to/file.txt" https://api.example.com/upload"#,
                    request("https://api.example.com/upload", method: "POST", body: parts(("file", .file(path: "/path/to/file.txt"))))),
        // Differs: Request Cookies rows, not a Cookie header ("Cookies become Request Cookies
        // rows"), here and in the next three cases.
        CurlFixture("should handle cookie flag", #"curl -b "session=abc123" https://api.example.com"#,
                    request("https://api.example.com", cookies: rows(("session", "abc123")))),
        CurlFixture("should handle cookie flag with multiple cookies", #"curl -b "session=abc123; user=john" https://api.example.com"#,
                    request("https://api.example.com", cookies: rows(("session", "abc123"), ("user", "john")))),
        CurlFixture("should handle multiple cookie flags", #"curl -b "session=abc123" -b "user=john" https://api.example.com"#,
                    request("https://api.example.com", cookies: rows(("session", "abc123"), ("user", "john")))),
        // secure and HttpOnly have no =, so they are dropped (the cookies node), as Bruno drops them.
        CurlFixture("should handle complex cookie string",
                    #"curl -b "session=abc123; user=john; path=/; domain=example.com; expires=Thu, 01 Jan 1970 00:00:00 GMT; secure; HttpOnly"              https://api.example.com"#,
                    request("https://api.example.com", cookies: rows(
                        ("session", "abc123"), ("user", "john"), ("path", "/"), ("domain", "example.com"),
                        ("expires", "Thu, 01 Jan 1970 00:00:00 GMT")))),
        // Differs: form-urlencoded (the body table), as in "should parse JSON data".
        CurlFixture("should handle shell quote patterns ('\\'' => \\')", #"curl -d '{"name": "John'\''s data"}' https://api.example.com"#,
                    request("https://api.example.com", method: "POST", body: .formURLEncoded(rows((#"{"name": "John's data"}"#, ""))))),
        // Differs: \' does not escape inside '…' in sh, so the quote closes at Don\ and a " opens
        // that never closes. bash rejects this command too (CurlLexer: POSIX shell words).
        CurlFixture("should handle complex escaped quotes", #"curl -d '{"message": "Don\'t stop believing"}' https://api.example.com"#,
                    throws: .unterminatedQuote(position: 44)),
        CurlFixture("should parse URLs with query parameters", "curl https://api.example.com/users?page=1&limit=10&sort=asc",
                    request("https://api.example.com/users", params: rows(("page", "1"), ("limit", "10"), ("sort", "asc")))),
        CurlFixture("should handle URLs with paths", "curl https://api.example.com/v1/users/123",
                    request("https://api.example.com/v1/users/123")),
        // Differs: http://, not https:// (the url node: curl prefixes http://), here and below.
        CurlFixture("should parse URL without protocol and default to https", "curl echo.usebruno.com",
                    request("http://echo.usebruno.com")),
        CurlFixture("should parse URL without protocol with path and query parameters", "curl api.example.com/users?page=1&limit=10",
                    request("http://api.example.com/users", params: rows(("page", "1"), ("limit", "10")))),
        // Differs: an unterminated quote, as in "should handle complex escaped quotes".
        CurlFixture("should parse a complex curl command with multiple features and no protocol",
                    #"curl -X POST              -H "Content-Type: application/json"              -H "Authorization: Bearer token123"              -H "X-Custom-Header: custom header"              -d '{"name": "John\'s data", "email": "john@example.com", "message": "Don\'t stop believing!", "path": "/home/user/file.txt", "json": {"nested": "value", "array": [1, 2, 3]}}'              -u "api_user:api_pass"              --compressed              api.example.com/v1/users?param1=value1&param2=custom+param"#,
                    throws: .unterminatedQuote(position: 384)),
        // Differs: --compressed sets nothing ("--compressed is ignored").
        CurlFixture("should handle compressed flag", "curl --compressed https://api.example.com",
                    request("https://api.example.com", ignored: ["--compressed"])),
        CurlFixture("should handle concatenated HTTP methods", "curl -XPOST https://api.example.com/users",
                    request("https://api.example.com/users", method: "POST")),
        CurlFixture("should handle newlines and continuations",
                    #"curl -H "Content-Type: application/json"              -d '{"name": "John"}'              https://api.example.com/users"#,
                    request("https://api.example.com/users", method: "POST", headers: json, body: .raw(.json, #"{"name": "John"}"#))),
        // Differs: an unterminated quote, as in "should handle complex escaped quotes".
        CurlFixture("should parse a complex curl command with multiple features",
                    #"curl -X POST              -H "Content-Type: application/json"              -H "Authorization: Bearer token123"              -H "X-Custom-Header: custom header"              -d '{"name": "John\'s data", "email": "john@example.com", "message": "Don\'t stop believing!", "path": "/home/user/file.txt", "json": {"nested": "value", "array": [1, 2, 3]}}'              -u "api_user:api_pass"              --compressed              https://api.example.com/v1/users?param1=value1&param2=custom+param"#,
                    throws: .unterminatedQuote(position: 384)),
        // Differs: an unterminated quote, as in "should handle complex escaped quotes".
        CurlFixture("should parse a curl command with complex escape characters",
                    #"curl -X POST              -H "Content-Type: application/json"              -H "Authorization: Bearer token123"              -d '{"name": "John\'s data", "email": "john@example.com"}'              -u "api_user:api_pass"              --compressed              https://api.example.com/v1/users"#,
                    throws: .unterminatedQuote(position: 218)),
        // Differs: Accept is added with Content-Type (the headers node: --json adds both, as curl
        // does), here and in every --json case below.
        CurlFixture("should handle basic JSON request",
                    #"curl --json '{"name": "John Doe", "email": "john@example.com"}'              https://api.example.com/users"#,
                    request("https://api.example.com/users", method: "POST", headers: jsonFlagHeaders,
                            body: .raw(.json, #"{"name": "John Doe", "email": "john@example.com"}"#))),
        // Differs: the Bearer header becomes Auth, as in "should parse multiple headers".
        CurlFixture("should handle JSON with authentication headers",
                    #"curl --json '{"title": "New Post", "content": "Post content"}'              -H "Authorization: Bearer token123"              https://api.example.com/posts"#,
                    request("https://api.example.com/posts", method: "POST", headers: jsonFlagHeaders,
                            body: .raw(.json, #"{"title": "New Post", "content": "Post content"}"#), auth: .bearer(token: "token123"))),
        CurlFixture("should handle complex JSON data",
                    #"curl --json '{"user": {"name": "Jane", "email": "jane@example.com"}, "metadata": {"source": "web"}}'              https://api.example.com/users"#,
                    request("https://api.example.com/users", method: "POST", headers: jsonFlagHeaders,
                            body: .raw(.json, #"{"user": {"name": "Jane", "email": "jane@example.com"}, "metadata": {"source": "web"}}"#))),
        // Differs: an unterminated quote, as in "should handle complex escaped quotes".
        CurlFixture("should handle JSON with escaped quotes",
                    #"curl --json '{"message": "Don\'t stop believing!", "user": "John\'s account"}'              https://api.example.com/messages"#,
                    throws: .unterminatedQuote(position: 76)),
        CurlFixture("should handle JSON with arrays and nested objects",
                    #"curl --json '{"items": [{"id": 1, "name": "Item 1"}, {"id": 2, "name": "Item 2"}], "total": 2}'              https://api.example.com/orders"#,
                    request("https://api.example.com/orders", method: "POST", headers: jsonFlagHeaders,
                            body: .raw(.json, #"{"items": [{"id": 1, "name": "Item 1"}, {"id": 2, "name": "Item 2"}], "total": 2}"#))),
        CurlFixture("should handle JSON with custom method",
                    #"curl -X PUT              --json '{"status": "completed", "updated_at": "2024-01-15T10:30:00Z"}'              https://api.example.com/tasks/123"#,
                    request("https://api.example.com/tasks/123", method: "PUT", headers: jsonFlagHeaders,
                            body: .raw(.json, #"{"status": "completed", "updated_at": "2024-01-15T10:30:00Z"}"#))),
        CurlFixture("should handle -k flag", "curl -k https://api.example.com",
                    request("https://api.example.com", insecure: true)),
        CurlFixture("should handle --insecure flag", "curl --insecure https://api.example.com",
                    request("https://api.example.com", insecure: true)),
        CurlFixture("should handle -G flag to convert POST data to GET query parameters",
                    #"curl -G -d "name=John" -d "age=30" https://api.example.com/users"#,
                    request("https://api.example.com/users", params: rows(("name", "John"), ("age", "30")))),
        // Differs: params are stored decoded ("John Doe", not "John%20Doe") and encoded at send, as
        // the URL bar's are; the URL's bare hello is an empty value, not undefined.
        CurlFixture("should handle -G flag with --data-urlencode",
                    #"curl -G --data-urlencode "name=John Doe"              --data-urlencode "email=john@example.com"              --data-urlencode "hello"              https://api.example.com/users?test=urlquery&hello"#,
                    request("https://api.example.com/users", params: rows(
                        ("test", "urlquery"), ("hello", ""), ("name", "John Doe"), ("email", "john@example.com"), ("hello", "")))),
        CurlFixture("should handle -G flag with complex data",
                    #"curl -G -d "search=test+query"              -d "filter=active"              -d "sort=name"              -d "page=1"              https://api.example.com/search"#,
                    request("https://api.example.com/search", params: rows(
                        ("search", "test+query"), ("filter", "active"), ("sort", "name"), ("page", "1")))),
    ]
}

struct BrunoCurlFixtureTests {
    @Test func `every Bruno test is ported`() {
        #expect(BrunoCurlFixtures.all.count == 53)
    }

    @Test(arguments: BrunoCurlFixtures.all)
    func `Bruno's curl fixtures import as Raccoon expects`(fixture: CurlFixture) {
        #expect(Result { () throws(CurlImportError) in try CurlImporter.import(fixture.input) } == fixture.expected)
    }
}

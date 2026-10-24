import Foundation
import RaccoonDomain
import Testing

struct PostmanImporterTests {
    func read(_ json: String) -> PostmanFile {
        PostmanImporter.read(Data(json.utf8))
    }

    /// A v2.1 Collection whose `item` array is `items`.
    func collection(_ items: String, rest: String = "") -> String {
        #"{"info": {"name": "C", "schema": "https://schema.getpostman.com/json/collection/v2.1.0/collection.json"}, "item": [\#(items)]\#(rest)}"#
    }

    func items(_ text: String) -> [PostmanItem] {
        guard case .collection(let collection) = read(text) else { return [] }
        return collection.items
    }

    func request(_ item: String) -> PostmanRequest? {
        guard case .request(let request) = items(collection(item)).first else { return nil }
        return request
    }

    @Test(arguments: [
        "garbage \u{0}\u{1} bytes {",
        "",
        "[1, 2]",
        #""a string""#,
        // A v1 Collection: `requests` and `order`, no `info.schema`.
        #"{"id": "c1", "name": "Old", "order": ["r1"], "requests": [{"id": "r1", "url": "http://h/", "method": "GET"}]}"#,
        // An Insomnia export.
        #"{"_type": "export", "__export_format": 4, "resources": [{"_type": "request", "name": "R", "url": "http://h/"}]}"#,
        // A v2.1 schema with no `item` array, and an `item` array with an unknown schema.
        #"{"info": {"name": "C", "schema": "https://schema.getpostman.com/json/collection/v2.1.0/collection.json"}}"#,
        #"{"info": {"name": "C", "schema": "https://schema.getpostman.com/json/collection/v3.0.0/collection.json"}, "item": []}"#,
        // A name with no `values`, and an unknown variable scope.
        #"{"name": "Dev"}"#,
        #"{"name": "Dev", "values": [], "_postman_variable_scope": "collection"}"#,
    ])
    func `bytes that are not a v2 Collection, an Environment or Globals are not a Postman export`(text: String) {
        #expect(read(text) == .notPostman)
    }
}

extension PostmanImporterTests {
    @Test(arguments: [
        (#""https://{{host}}/users?page=2""#, PostmanURL(raw: "https://{{host}}/users?page=2")),
        (
            #"{"raw": "https://api.example.com:8080/v1/users/:id?page=2#top", "protocol": "https", "host": ["api", "example", "com"], "port": "8080", "path": ["v1", "users", ":id"], "query": [{"key": "page", "value": "2"}, {"key": "old", "value": null, "disabled": true}], "variable": [{"key": "id", "value": 7}], "hash": "top"}"#,
            PostmanURL(
                raw: "https://api.example.com:8080/v1/users/:id?page=2#top", protocol: "https", host: ["api", "example", "com"],
                port: "8080", path: ["v1", "users", ":id"],
                query: [PostmanKeyValue(key: "page", value: "2"), PostmanKeyValue(key: "old", value: "", disabled: true)],
                variable: [PostmanKeyValue(key: "id", value: "7")], hash: "top"
            )
        ),
        (
            #"{"host": "api.example.com", "path": "/v1/users/:id"}"#,
            PostmanURL(host: ["api", "example", "com"], path: ["v1", "users", ":id"])
        ),
        (#"{"host": "{{base}}", "path": ""}"#, PostmanURL(host: ["{{base}}"], path: [])),
        (#"{"raw": "{{base}}/a"}"#, PostmanURL(raw: "{{base}}/a")),
        ("null", PostmanURL()),
    ])
    func `url is a string, or an object whose host and path are arrays or strings`(json: String, url: PostmanURL) {
        #expect(request(#"{"name": "R", "request": {"url": \#(json)}}"#)?.url == url)
    }
}

extension PostmanImporterTests {
    static let values = #"""
        [{"key": "host", "value": "https://api.example.com", "type": "default", "enabled": true},
         {"key": "token", "value": "sk_1", "type": "secret", "enabled": true},
         {"key": "port", "value": 8080},
         {"key": "old", "value": "x", "enabled": false}]
        """#
    static let variables = [
        PostmanVariable(key: "host", value: "https://api.example.com", type: "default"),
        PostmanVariable(key: "token", value: "sk_1", type: "secret"),
        PostmanVariable(key: "port", value: "8080"),
        PostmanVariable(key: "old", value: "x", enabled: false),
    ]

    @Test(arguments: [
        #"{"id": "e1", "name": "Dev", "values": \#(values), "_postman_variable_scope": "environment"}"#,
        #"{"name": "Dev", "values": \#(values)}"#,
    ])
    func `an Environment is its scope, or a name with values`(json: String) {
        #expect(read(json) == .environment(PostmanEnvironment(name: "Dev", values: Self.variables)))
    }

    @Test func `Globals are their scope, whatever their name`() {
        #expect(read(#"{"name": "My Workspace Globals", "values": \#(Self.values), "_postman_variable_scope": "globals"}"#) == .globals(Self.variables))
    }
}

extension PostmanImporterTests {
    @Test func `folders nest to any depth in order, and an item with neither item nor request is kept as other`() {
        // Yaak's nested.input.json, plus an item with neither.
        let text = collection(#"""
            {"name": "Top Folder", "item": [
                {"name": "Nested Folder", "item": [{"name": "Request 1", "request": {"method": "GET"}}]},
                {"name": "Request 2", "request": {"method": "GET"}}
            ]},
            {"name": "Request 3", "request": {"method": "GET"}},
            {"name": "Stray"},
            "not an object"
            """#)

        #expect(items(text) == [
            .folder(PostmanFolder(name: "Top Folder", items: [
                .folder(PostmanFolder(name: "Nested Folder", items: [.request(PostmanRequest(name: "Request 1"))])),
                .request(PostmanRequest(name: "Request 2")),
            ])),
            .request(PostmanRequest(name: "Request 3")),
            .other(name: "Stray"),
        ])
    }

    @Test func `a collection and its folders keep their description, auth, scripts and variables`() {
        let text = #"""
            {"info": {"name": "Shop", "description": {"content": "The shop API", "type": "text/markdown"},
                      "schema": "https://schema.getpostman.com/json/collection/v2.0.0/collection.json"},
             "item": [{"name": "F", "description": "Folder notes", "item": [],
                       "auth": {"type": "bearer", "bearer": [{"key": "token", "value": "f-token", "type": "string"}]},
                       "event": [{"listen": "test", "script": {"type": "text/javascript", "exec": ["pm.test(1);", "pm.test(2);"]}}]}],
             "auth": {"type": "basic", "basic": [{"key": "password", "value": "pass"}, {"key": "username", "value": "user"}]},
             "event": [{"listen": "prerequest", "script": {"exec": "console.log(1)"}}],
             "variable": [{"key": "base", "value": "https://shop.test"}, {"key": "off", "value": true, "disabled": true}]}
            """#

        #expect(read(text) == .collection(PostmanCollection(
            name: "Shop", description: "The shop API",
            items: [.folder(PostmanFolder(
                name: "F", description: "Folder notes", items: [],
                auth: PostmanAuth(type: "bearer", parameters: ["token": "f-token"]),
                events: [PostmanEvent(listen: "test", exec: "pm.test(1);\npm.test(2);")]
            ))],
            auth: PostmanAuth(type: "basic", parameters: ["username": "user", "password": "pass"]),
            events: [PostmanEvent(listen: "prerequest", exec: "console.log(1)")],
            variables: [PostmanVariable(key: "base", value: "https://shop.test"), PostmanVariable(key: "off", value: "true", enabled: false)]
        )))
    }
}

extension PostmanImporterTests {
    @Test func `a request keeps its method, headers, auth, settings, scripts and the count of its examples`() {
        let item = #"""
            {"name": "Create", "description": "Item notes",
             "protocolProfileBehavior": {"followRedirects": false, "strictSSL": false, "disableBodyPruning": true},
             "event": [{"listen": "test", "script": {"exec": [""]}}],
             "request": {"method": "POST", "description": {"content": "Request notes"},
                         "header": [{"key": "X-Foo", "value": "bar", "description": "d"}, {"key": "Off", "value": 1, "disabled": true}],
                         "auth": {"type": "apikey", "apikey": [{"key": "in", "value": "query"}, {"key": "key", "value": "api_key"}, {"key": "value", "value": "{{key}}"}]},
                         "url": "https://h/"},
             "response": [{"name": "200"}, {"name": "404"}]}
            """#

        #expect(request(item) == PostmanRequest(
            name: "Create", description: "Request notes", method: "POST", url: PostmanURL(raw: "https://h/"),
            headers: [PostmanKeyValue(key: "X-Foo", value: "bar"), PostmanKeyValue(key: "Off", value: "1", disabled: true)],
            auth: PostmanAuth(type: "apikey", parameters: ["in": "query", "key": "api_key", "value": "{{key}}"]),
            followRedirects: false, strictSSL: false,
            events: [PostmanEvent(listen: "test", exec: "")], responseCount: 2
        ))
    }

    @Test func `a request with no description of its own keeps the item's, and a bare URL string is a GET`() {
        #expect(request(#"{"name": "R", "description": "Item notes", "request": {}}"#)?.description == "Item notes")
        #expect(request(#"{"name": "R", "request": "https://h/"}"#) == PostmanRequest(name: "R", url: PostmanURL(raw: "https://h/")))
    }

    @Test(arguments: [
        (#"{"type": "inherit"}"#, PostmanAuth(type: "inherit")),
        (#"{"type": "noauth"}"#, PostmanAuth(type: "noauth")),
        (#"{"type": "bearer", "bearer": {"token": "v2.0-style"}}"#, PostmanAuth(type: "bearer", parameters: ["token": "v2.0-style"])),
        (#"{"type": "oauth2", "oauth2": [{"key": "addTokenTo", "value": "header"}, {"key": "useBrowser", "value": false}]}"#,
         PostmanAuth(type: "oauth2", parameters: ["addTokenTo": "header", "useBrowser": "false"])),
    ] as [(String, PostmanAuth)])
    func `auth is its type and that type's parameters`(json: String, auth: PostmanAuth) {
        #expect(request(#"{"name": "R", "request": {"auth": \#(json)}}"#)?.auth == auth)
    }

    @Test func `no auth on a request is nil, which Postman reads as inherit`() {
        #expect(request(#"{"name": "R", "request": {"auth": null}}"#)?.auth == nil)
    }
}

extension PostmanImporterTests {
    @Test(arguments: [
        (#"{"mode": "raw", "raw": "{\"a\": 1}", "options": {"raw": {"language": "json"}}}"#, PostmanBody.raw(#"{"a": 1}"#, language: "json")),
        (#"{"mode": "raw", "raw": "plain"}"#, .raw("plain", language: nil)),
        (#"{"mode": "urlencoded", "urlencoded": [{"key": "a", "value": "1"}, {"key": "b", "value": "2", "disabled": true}]}"#,
         .urlencoded([PostmanKeyValue(key: "a", value: "1"), PostmanKeyValue(key: "b", value: "2", disabled: true)])),
        (#"{"mode": "formdata", "formdata": [{"key": "t", "value": "x", "type": "text"}, {"key": "f", "type": "file", "src": "/tmp/a.png"}, {"key": "fs", "type": "file", "src": ["a", "b"], "disabled": true}, {"key": "none", "type": "file", "src": null}]}"#,
         .formdata([
            PostmanFormParameter(key: "t", content: .text("x")),
            PostmanFormParameter(key: "f", content: .file(src: ["/tmp/a.png"])),
            PostmanFormParameter(key: "fs", content: .file(src: ["a", "b"]), disabled: true),
            PostmanFormParameter(key: "none", content: .file(src: [])),
         ])),
        (#"{"mode": "graphql", "graphql": {"query": "{ me { id } }", "variables": "{\"a\": 1}"}}"#, .graphql(query: "{ me { id } }", variables: #"{"a": 1}"#)),
        (#"{"mode": "graphql", "graphql": {"query": "q", "variables": {"a": 1}}}"#, .graphql(query: "q", variables: #"{"a":1}"#)),
        (#"{"mode": "file", "file": {"src": "body.bin"}}"#, .file(src: "body.bin")),
        (#"{"mode": "file", "file": {}}"#, .file(src: nil)),
    ] as [(String, PostmanBody)])
    func `the body is read by its mode`(json: String, body: PostmanBody) {
        #expect(request(#"{"name": "R", "request": {"body": \#(json)}}"#)?.body == body)
    }

    @Test(arguments: [#"{"mode": "unknown"}"#, #"{}"#, "null"])
    func `an unknown mode is no body`(json: String) {
        #expect(request(#"{"name": "R", "request": {"body": \#(json)}}"#)?.body == nil)
    }
}

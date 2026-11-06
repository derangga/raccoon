import Foundation
import RaccoonDomain
import Testing

struct PostmanExporterTests {
    static let exportID = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!
    static let schema = "https://schema.getpostman.com/json/collection/v2.1.0/collection.json"

    static func request(_ name: String = "r", _ definition: RequestDefinition = .empty) -> ExportNode {
        .request(Request(id: RequestID(UUID()), name: name, definition: definition))
    }

    static func export(_ nodes: [ExportNode], name: String = "C") -> Data {
        PostmanExporter.collection(ExportCollection(name: name, nodes: nodes), id: exportID)
    }

    static func json(_ data: Data) throws -> NSDictionary {
        try #require(JSONSerialization.jsonObject(with: data) as? NSDictionary)
    }

    /// The parsed JSON at `keyPath` of the one Request's item, e.g. `request.url`.
    static func item(_ definition: RequestDefinition, at keyPath: String? = nil) throws -> Any {
        let items = try #require(try json(export([request("r", definition)]))["item"] as? [NSDictionary])
        let item = try #require(items.first)
        return try #require(keyPath.map { item.value(forKeyPath: $0) } ?? item)
    }

    static func parsed(_ text: String) throws -> Any {
        try JSONSerialization.jsonObject(with: Data(text.utf8), options: .fragmentsAllowed)
    }

    static func same(_ actual: Any, _ expected: String) throws -> Bool {
        try (actual as AnyObject).isEqual(parsed(expected))
    }

    @Test func `a Collection is its info and its items, and nothing Raccoon has no value for`() throws {
        let file = try Self.json(Self.export([], name: "My API"))
        #expect(Set(file.allKeys as? [String] ?? []) == ["info", "item"])
        #expect(try Self.same(file["info"]!, #"{"name": "My API", "_postman_id": "11111111-2222-3333-4444-555555555555", "schema": "\#(Self.schema)"}"#))
        #expect(try Self.same(file["item"]!, "[]"))
    }

    @Test func `a Folder is an item with item, at any depth, and an empty one is an empty array`() throws {
        let nodes: [ExportNode] = [.folder(name: "A", children: [.folder(name: "B", children: []), Self.request("x")])]
        let file = try Self.json(Self.export(nodes))
        let folder = try #require((file["item"] as? [NSDictionary])?.first)
        #expect(Set(folder.allKeys as? [String] ?? []) == ["name", "item"])
        let children = try #require(folder["item"] as? [NSDictionary])
        #expect(try Self.same(children[0], #"{"name": "B", "item": []}"#))
        #expect(children[1]["name"] as? String == "x")
    }

    @Test func `items keep the order they are given`() throws {
        let nodes: [ExportNode] = [Self.request("z"), .folder(name: "b", children: []), Self.request("a")]
        let names = (try Self.json(Self.export(nodes))["item"] as? [NSDictionary])?.compactMap { $0["name"] as? String }
        #expect(names == ["z", "b", "a"])
    }

    @Test func `a Request is an item with its name, request and an empty response, and no RequestID`() throws {
        let item = try #require(try Self.item(.empty) as? NSDictionary)
        #expect(Set(item.allKeys as? [String] ?? []) == ["name", "request", "response", "protocolProfileBehavior"])
        #expect(item["name"] as? String == "r")
        #expect(try Self.same(item["response"]!, "[]"))
    }
}

extension PostmanExporterTests {
    static func definition(
        method: String = "GET", url: String = "", params: [Row] = [], pathVariables: [String: String] = [:], headers: [Row] = [],
        cookies: [Row] = [], body: Body = .none, auth: Auth = .none, insecure: Bool = false, redirects: Bool = false,
        originalMethod: Bool = false, authorization: Bool = false, maxRedirects: Int = 20, timeoutSeconds: Int? = nil
    ) -> RequestDefinition {
        RequestDefinition(
            method: method, url: url, params: params, pathVariables: pathVariables, headers: headers, cookies: cookies, body: body, auth: auth,
            settings: RequestSettings(allowsInsecureTLS: insecure, followsRedirects: redirects, followsOriginalMethod: originalMethod,
                                      followsAuthorizationHeader: authorization, maxRedirects: maxRedirects, timeoutSeconds: timeoutSeconds)
        )
    }

    @Test(arguments: ["GET", "POST", "PURGE"])
    func `method is request.method`(method: String) throws {
        #expect(try Self.item(Self.definition(method: method), at: "request.method") as? String == method)
    }

    @Test(arguments: [
        // everything outside {{ }} is split; raw is the URL bar's text
        ("https://api.example.com:8080/v1/users", [Row](),
         #"{"raw": "https://api.example.com:8080/v1/users", "protocol": "https", "host": ["api", "example", "com"], "port": "8080", "path": ["v1", "users"]}"#),
        // enabled Params are in raw, every Param is in query as typed, a Disabled Row says so
        ("http://h/p", [Row(name: "a b", value: "x&y"), Row(name: "off", value: "1", isEnabled: false)],
         #"{"raw": "http://h/p?a%20b=x%26y", "protocol": "http", "host": ["h"], "path": ["p"], "query": [{"key": "a b", "value": "x&y"}, {"key": "off", "value": "1", "disabled": true}]}"#),
        // no scheme: no protocol; a port is digits after the last colon of the host
        ("localhost:3000/x", [Row](), #"{"raw": "localhost:3000/x", "host": ["localhost"], "port": "3000", "path": ["x"]}"#),
        // a variable is never split, whatever it holds
        ("{{scheme}}://{{api.host}}/a/{{p/q}}", [Row](),
         #"{"raw": "{{scheme}}://{{api.host}}/a/{{p/q}}", "protocol": "{{scheme}}", "host": ["{{api.host}}"], "path": ["a", "{{p/q}}"]}"#),
        ("{{base}}/users", [Row](), #"{"raw": "{{base}}/users", "host": ["{{base}}"], "path": ["users"]}"#),
        // no path: no path key
        ("https://h.io", [Row](), #"{"raw": "https://h.io", "protocol": "https", "host": ["h", "io"]}"#),
        ("", [Row(name: "k", value: "v")], #"{"raw": "?k=v", "query": [{"key": "k", "value": "v"}]}"#),
        ("", [Row](), #"{"raw": ""}"#),
    ])
    func `url and Params are request.url`(url: String, params: [Row], expected: String) throws {
        let actual = try Self.item(Self.definition(url: url, params: params), at: "request.url")
        #expect(try Self.same(actual, expected), "\(actual)")
    }

    @Test func `a Disabled Param is left out of raw`() throws {
        let raw = try Self.item(Self.definition(url: "http://h", params: [Row(name: "a", value: "1", isEnabled: false)]), at: "request.url.raw")
        #expect(raw as? String == "http://h")
    }

    @Test(arguments: [
        ("http://h/u/:id/p/:id/:name", ["id": "5"],
         #"{"raw": "http://h/u/:id/p/:id/:name", "protocol": "http", "host": ["h"], "path": ["u", ":id", "p", ":id", ":name"], "variable": [{"key": "id", "value": "5"}, {"key": "name", "value": ""}]}"#),
        ("http://h:8080/u", [String: String](), #"{"raw": "http://h:8080/u", "protocol": "http", "host": ["h"], "port": "8080", "path": ["u"]}"#),
    ])
    func `Path Variables stay in path and url.variable has one entry per distinct name`(url: String, values: [String: String], expected: String) throws {
        let actual = try Self.item(Self.definition(url: url, pathVariables: values), at: "request.url")
        #expect(try Self.same(actual, expected), "\(actual)")
    }

    @Test func `headers are key and value in row order, a Disabled Row says so, and none has a type`() throws {
        let headers = [Row(name: "B", value: "2"), Row(name: "A", value: "1", isEnabled: false), Row(name: "Content-Type", value: "text/plain")]
        let actual = try Self.item(Self.definition(headers: headers), at: "request.header")
        #expect(try Self.same(actual, #"[{"key": "B", "value": "2"}, {"key": "A", "value": "1", "disabled": true}, {"key": "Content-Type", "value": "text/plain"}]"#))
    }

    @Test func `no header is added for what the send computes`() throws {
        let body = Body.raw(.json, "{}")
        #expect(try Self.same(Self.item(Self.definition(body: body), at: "request.header"), "[]"))
    }

    @Test func `each run of Request Cookies is one Cookie header, and a Disabled run says so`() throws {
        let cookies = [
            Row(name: "a", value: "1"), Row(name: "b", value: "2"),
            Row(name: "c", value: "3", isEnabled: false), Row(name: "d", value: "{{t}}", isEnabled: false),
            Row(name: "e", value: "5"),
        ]
        let actual = try Self.item(Self.definition(headers: [Row(name: "X", value: "y")], cookies: cookies), at: "request.header")
        #expect(try Self.same(actual, """
        [{"key": "X", "value": "y"}, {"key": "Cookie", "value": "a=1; b=2"}, {"key": "Cookie", "value": "c=3; d={{t}}", "disabled": true}, {"key": "Cookie", "value": "e=5"}]
        """))
    }

    @Test(arguments: [
        (Body.none, nil),
        (.raw(.json, #"{"a": 1}"#), #"{"mode": "raw", "raw": "{\"a\": 1}", "options": {"raw": {"language": "json"}}}"#),
        (.raw(.xml, "<a/>"), #"{"mode": "raw", "raw": "<a/>", "options": {"raw": {"language": "xml"}}}"#),
        (.raw(.text, "hi"), #"{"mode": "raw", "raw": "hi", "options": {"raw": {"language": "text"}}}"#),
        (.formURLEncoded([Row(name: "a", value: "1"), Row(name: "b", value: "2", isEnabled: false)]),
         #"{"mode": "urlencoded", "urlencoded": [{"key": "a", "value": "1"}, {"key": "b", "value": "2", "disabled": true}]}"#),
        (.multipart([
            Part(name: "t", content: .text("v")),
            Part(name: "f", isEnabled: false, content: .file(path: "/Users/me/a.png")),
         ]),
         #"{"mode": "formdata", "formdata": [{"key": "t", "value": "v", "type": "text"}, {"key": "f", "type": "file", "src": "/Users/me/a.png", "disabled": true}]}"#),
    ])
    func `Body is request.body, and none is no key`(body: Body, expected: String?) throws {
        let item = try #require(try Self.item(Self.definition(body: body), at: "request") as? NSDictionary)
        guard let expected else { #expect(item["body"] == nil); return }
        #expect(try Self.same(#require(item["body"]), expected), "\(item)")
    }

    @Test(arguments: [
        (Auth.none, #"{"type": "noauth"}"#),
        (.basic(user: "u", password: "{{p}}"),
         #"{"type": "basic", "basic": [{"key": "username", "value": "u", "type": "string"}, {"key": "password", "value": "{{p}}", "type": "string"}]}"#),
        (.bearer(token: "t"), #"{"type": "bearer", "bearer": [{"key": "token", "value": "t", "type": "string"}]}"#),
    ])
    func `Auth is request.auth, and none is noauth on every Request`(auth: Auth, expected: String) throws {
        #expect(try Self.same(Self.item(Self.definition(auth: auth), at: "request.auth"), expected))
    }

    @Test(arguments: [
        ("GET", Body.none, false, false, #"{"followRedirects": false, "maxRedirects": 20, "followOriginalHttpMethod": false, "followAuthorizationHeader": false}"#),
        ("POST", .none, true, true, #"{"followRedirects": true, "strictSSL": false, "maxRedirects": 20, "followOriginalHttpMethod": false, "followAuthorizationHeader": false}"#),
        ("GET", .raw(.text, "x"), false, false, #"{"followRedirects": false, "disableBodyPruning": true, "maxRedirects": 20, "followOriginalHttpMethod": false, "followAuthorizationHeader": false}"#),
        ("HEAD", .formURLEncoded([Row(name: "a", value: "1")]), false, true, #"{"followRedirects": true, "disableBodyPruning": true, "maxRedirects": 20, "followOriginalHttpMethod": false, "followAuthorizationHeader": false}"#),
        ("POST", .raw(.text, "x"), false, true, #"{"followRedirects": true, "maxRedirects": 20, "followOriginalHttpMethod": false, "followAuthorizationHeader": false}"#),
    ])
    func `Request Settings are protocolProfileBehavior`(method: String, body: Body, insecure: Bool, redirects: Bool, expected: String) throws {
        let definition = Self.definition(method: method, body: body, insecure: insecure, redirects: redirects)
        #expect(try Self.same(Self.item(definition, at: "protocolProfileBehavior"), expected))
    }

    @Test func `a variable is written as typed, and no description or event is written`() throws {
        let definition = Self.definition(
            url: "{{base}}/a", headers: [Row(name: "X", value: "{{v}}")], body: .raw(.text, "{{b}}"), auth: .bearer(token: "{{t}}")
        )
        let item = try #require(try Self.item(definition) as? NSDictionary)
        let text = String(decoding: try JSONSerialization.data(withJSONObject: item), as: UTF8.self)
        for name in ["{{base}}", "{{v}}", "{{b}}", "{{t}}"] { #expect(text.contains(name)) }
        #expect(item["description"] == nil && item["event"] == nil)
        #expect((item["request"] as? NSDictionary)?["description"] == nil)
    }
}

extension PostmanExporterTests {
    @Test func `two exports of one Collection are byte-equal and end in a newline`() {
        let nodes: [ExportNode] = [.folder(name: "F", children: [Self.request("a", Self.definition(url: "http://h/:id", headers: [Row(name: "X", value: "1")]))])]
        let first = Self.export(nodes)
        #expect(first == Self.export(nodes))
        #expect(first.last == UInt8(ascii: "\n"))
        let text = String(decoding: first, as: UTF8.self)
        #expect(text.contains(#""schema" : "\#(Self.schema)""#))
        #expect(text.contains("\n  \"info\""))
        // sorted keys: info before item
        #expect(text.range(of: "\"info\"")!.lowerBound < text.range(of: "\"item\"")!.lowerBound)
    }

    @Test func `only the id differs between exports with different ids`() {
        let one = String(decoding: Self.export([]), as: UTF8.self).split(separator: "\n")
        let two = String(decoding: PostmanExporter.collection(ExportCollection(name: "C", nodes: []), id: UUID()), as: UTF8.self).split(separator: "\n")
        #expect(one.count == two.count)
        #expect(zip(one, two).count { $0 != $1 } == 1)
    }
}

extension PostmanExporterTests {
    /// Plans one Collection into an empty Workspace, RequestIDs counted from 1.
    static func plan(_ data: Data) -> ImportPlan {
        var next = 0
        return PostmanMapping.plan(
            [PostmanImporter.read(data)], dataFolder: DataFolderIndex([]), globals: Globals(entries: []), environments: []
        ) {
            next += 1
            return PostmanMappingTests.id(next)
        }
    }

    static func node(_ node: ImportNode) -> ExportNode {
        switch node {
        case .folder(let name, let children): .folder(name: name, children: children.map(Self.node))
        case .request(let request): .request(request)
        }
    }

    /// `definition` exported, then read and planned again.
    static func roundTrip(_ definition: RequestDefinition) throws -> (RequestDefinition, [ImportNote]) {
        let plan = plan(export([request("r", definition)]))
        guard case .request(let again)? = plan.collections.first?.nodes.first else { throw RoundTripFailed() }
        return (again.definition, plan.notes)
    }

    struct RoundTripFailed: Error {}

    static let json = Row(name: "Content-Type", value: "application/json")

    static let roundTrips: [RequestDefinition] = [
        definition(),
        definition(method: "PURGE", url: "http://h:8080/a/b", redirects: true),
        definition(url: "https://{{host}}/v1/:id/x/:name", pathVariables: ["id": "5", "name": "{{n}}"]),
        definition(url: "http://h/p", params: [Row(name: "a b", value: "x&y"), Row(name: "off", value: "1", isEnabled: false), Row(name: "{{k}}", value: "{{v}}")]),
        definition(url: "http://h", params: [Row(name: "only", value: "disabled", isEnabled: false)]),
        definition(headers: [Row(name: "A", value: "1"), Row(name: "B", value: "2", isEnabled: false)]),
        definition(cookies: [Row(name: "a", value: "1"), Row(name: "b", value: "2"), Row(name: "c", value: "3", isEnabled: false), Row(name: "d", value: "4")]),
        definition(method: "POST", headers: [json], body: .raw(.json, #"{"a": "{{b}}"}"#)),
        definition(method: "POST", headers: [Row(name: "Content-Type", value: "application/xml")], body: .raw(.xml, "<a/>")),
        definition(method: "POST", headers: [Row(name: "Content-Type", value: "text/plain")], body: .raw(.text, "hi")),
        definition(
            method: "POST", headers: [Row(name: "Content-Type", value: "application/x-www-form-urlencoded")],
            body: .formURLEncoded([Row(name: "a", value: "1"), Row(name: "b", value: "2", isEnabled: false)])
        ),
        definition(
            method: "POST", headers: [Row(name: "Content-Type", value: "multipart/form-data")],
            body: .multipart([Part(name: "t", content: .text("v")), Part(name: "f", isEnabled: false, content: .file(path: "/Users/me/a.png"))])
        ),
        definition(auth: .basic(user: "u", password: "p")),
        definition(auth: .bearer(token: "{{t}}")),
        definition(insecure: true, redirects: true),
        definition(redirects: true, originalMethod: true, authorization: true, maxRedirects: 5),
        definition(redirects: false, maxRedirects: 0),
        definition(method: "GET", headers: [json], body: .raw(.json, "{}")),
    ]

    @Test(arguments: roundTrips)
    func `a RequestDefinition read again is equal, with no note`(definition: RequestDefinition) throws {
        let (again, notes) = try Self.roundTrip(definition)
        #expect(again == definition)
        #expect(notes == [])
    }

    @Test(arguments: [Body.raw(.json, ""), .formURLEncoded([]), .multipart([])])
    func `an empty body is read again as none`(body: Body) throws {
        let (again, notes) = try Self.roundTrip(Self.definition(method: "POST", body: body))
        #expect(again == Self.definition(method: "POST"))
        #expect(notes == [])
    }

    @Test func `a body with no Content-Type row gets one when read again`() throws {
        let (again, notes) = try Self.roundTrip(Self.definition(method: "POST", body: .raw(.json, "{}")))
        #expect(again == Self.definition(method: "POST", headers: [Self.json], body: .raw(.json, "{}")))
        #expect(notes == [])
    }

    @Test func `a file Part with a relative path and a dynamic variable come back with a note`() throws {
        let definition = Self.definition(
            method: "POST", url: "http://h/{{$guid}}", headers: [Row(name: "Content-Type", value: "multipart/form-data")],
            body: .multipart([Part(name: "f", content: .file(path: "a.png"))])
        )
        let (again, notes) = try Self.roundTrip(definition)
        #expect(again == definition)
        #expect(notes == [
            ImportNote(.fileOnlyName(path: "a.png"), names: ["r"]),
            ImportNote(.dynamicVariable(name: "$guid"), names: ["r"]),
        ])
    }

    @Test func `a header named Cookie is read again as a Request Cookie`() throws {
        let (again, _) = try Self.roundTrip(Self.definition(headers: [Row(name: "cookie", value: "a=1")]))
        #expect(again == Self.definition(cookies: [Row(name: "a", value: "1")]))
    }

    /// `example/` is untracked (it holds real tokens), so a clone without it skips the tests that read it.
    static let sample = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appending(path: "example/Sociolla.postman_collection.json")
    static let hasSample = FileManager.default.fileExists(atPath: sample.path)

    @Test(.enabled(if: PostmanExporterTests.hasSample))
    func `the example Collection exports and reads back to the same plan, in plan order`() throws {
        let first = Self.plan(try Data(contentsOf: Self.sample))
        let collection = try #require(first.collections.first)
        let exported = PostmanExporter.collection(ExportCollection(name: collection.name, nodes: collection.nodes.map(Self.node)), id: Self.exportID)
        let second = Self.plan(exported)
        #expect(second.collections == first.collections)
        #expect(second.notes == [])

        func count(_ nodes: [ImportNode]) -> (requests: Int, folders: Int) {
            nodes.reduce((0, 0)) { total, node in
                switch node {
                case .request: (total.0 + 1, total.1)
                case .folder(_, let children): (total.0 + count(children).requests, total.1 + 1 + count(children).folders)
                }
            }
        }
        #expect(count(collection.nodes) == (41, 11))
    }

    /// The importer's fixtures run backwards: each planned Collection is exported and planned again.
    /// A fixture that hits a listed exception is skipped by name.
    static let skipped: Set<String> = []

    @Test(arguments: PostmanMappingTests.fixtures)
    func `a planned fixture Collection exports and reads back to the same plan`(fixture: PostmanFixture) {
        guard !Self.skipped.contains(fixture.name) else { return }
        for collection in fixture.expected.collections {
            let exported = PostmanExporter.collection(ExportCollection(name: collection.name, nodes: collection.nodes.map(Self.node)), id: Self.exportID)
            #expect(Self.plan(exported).collections == [collection], "\(fixture.name)")
        }
    }
}

// Environment export

extension PostmanExporterTests {
    static let exportedAt = Date(timeIntervalSince1970: 1_793_948_987.5)

    static func name(_ text: String) -> VariableName { VariableName(text)! }

    static func exportEnvironment(
        _ entries: [VariableEntry], secrets: EnvironmentSecrets = .none, name: String = "E"
    ) -> Data {
        PostmanExporter.environment(
            Environment(name: name, entries: entries), secrets: secrets, id: exportID, exportedAt: exportedAt, version: "1.2.3"
        )
    }

    struct EnvironmentRow: Sendable, CustomTestStringConvertible {
        let label: String
        let entry: VariableEntry
        let secrets: [String: String]
        let expected: String
        var testDescription: String { label }
    }

    static let environmentRows = [
        EnvironmentRow(
            label: "a plain entry is type default with its value",
            entry: VariableEntry(name: name("host"), value: .plain("https://x.io")), secrets: [:],
            expected: #"{"key":"host","value":"https://x.io","type":"default","enabled":true}"#
        ),
        EnvironmentRow(
            label: "a disabled entry keeps enabled false",
            entry: VariableEntry(name: name("off"), isEnabled: false, value: .plain("1")), secrets: [:],
            expected: #"{"key":"off","value":"1","type":"default","enabled":false}"#
        ),
        EnvironmentRow(
            label: "a secret with a value in the map is type secret with that value",
            entry: VariableEntry(name: name("token"), value: .secret), secrets: ["token": "s3cret"],
            expected: #"{"key":"token","value":"s3cret","type":"secret","enabled":true}"#
        ),
        EnvironmentRow(
            label: "a secret absent from the map is written as an empty string",
            entry: VariableEntry(name: name("token"), value: .secret), secrets: [:],
            expected: #"{"key":"token","value":"","type":"secret","enabled":true}"#
        ),
        EnvironmentRow(
            label: "a disabled secret keeps its value and enabled false",
            entry: VariableEntry(name: name("token"), isEnabled: false, value: .secret), secrets: ["token": "s3cret"],
            expected: #"{"key":"token","value":"s3cret","type":"secret","enabled":false}"#
        ),
    ]

    @Test(arguments: environmentRows)
    func `an Environment entry is one values item`(row: EnvironmentRow) throws {
        let secrets = EnvironmentSecrets(values: Dictionary(uniqueKeysWithValues: row.secrets.map { (Self.name($0.key), $0.value) }), unreadable: [])
        let values = try #require(try Self.json(Self.exportEnvironment([row.entry], secrets: secrets))["values"] as? [Any])
        #expect(values.count == 1)
        #expect(try Self.same(values[0], row.expected))
    }

    @Test func `an Environment file has the id, name, scope, date and Raccoon version, and a null color`() throws {
        let file = try Self.json(Self.exportEnvironment([], name: "Staging"))
        #expect(Set(file.allKeys.map { "\($0)" }) == Self.environmentKeys)
        #expect(file["id"] as? String == "11111111-2222-3333-4444-555555555555")
        #expect(file["name"] as? String == "Staging")
        #expect(file["color"] is NSNull)
        #expect(file["_postman_variable_scope"] as? String == "environment")
        #expect(file["_postman_exported_at"] as? String == "2026-11-06T07:09:47.500Z")
        #expect(file["_postman_exported_using"] as? String == "Raccoon/1.2.3")
        #expect(file["values"] as? [Any] != nil)
    }

    /// The keys of `example/Sociolla Beauty Journal.postman_environment.json`, at the top and in each value.
    static let environmentKeys: Set<String> = ["id", "name", "values", "color", "_postman_variable_scope", "_postman_exported_at", "_postman_exported_using"]
    static let environmentValueKeys: Set<String> = ["key", "value", "type", "enabled"]

    /// Like `sample`, `example/` is untracked: a clone without the file skips the test that reads it.
    static let sampleEnvironment = sample.deletingLastPathComponent().appending(path: "Sociolla Beauty Journal.postman_environment.json")
    static let hasSampleEnvironment = FileManager.default.fileExists(atPath: sampleEnvironment.path)

    @Test(.enabled(if: PostmanExporterTests.hasSampleEnvironment))
    func `the example Environment and its export have the same keys at the top and in each value`() throws {
        let example = try Self.json(try Data(contentsOf: Self.sampleEnvironment))
        let entries = [
            VariableEntry(name: Self.name("a"), value: .plain("1")),
            VariableEntry(name: Self.name("b"), isEnabled: false, value: .secret),
        ]
        let ours = try Self.json(Self.exportEnvironment(entries, secrets: EnvironmentSecrets(values: [Self.name("b"): "x"], unreadable: [])))
        #expect(Set(ours.allKeys.map { "\($0)" }) == Set(example.allKeys.map { "\($0)" }))
        let exampleValues = try #require(example["values"] as? [NSDictionary])
        for value in try #require(ours["values"] as? [NSDictionary]) + exampleValues {
            #expect(Set(value.allKeys.map { "\($0)" }) == Self.environmentValueKeys)
        }
    }

    @Test func `an Environment is read again as the same entries, with secrets still secrets`() throws {
        let entries = [
            VariableEntry(name: Self.name("host"), value: .plain("https://x.io")),
            VariableEntry(name: Self.name("off"), isEnabled: false, value: .plain("")),
            VariableEntry(name: Self.name("token"), value: .secret),
            VariableEntry(name: Self.name("empty"), isEnabled: false, value: .secret),
            VariableEntry(name: Self.name("a.b-c_d"), value: .plain("é \"q\" \\ 日本語 😀\nline {{x}}")),
        ]
        let data = Self.exportEnvironment(entries, secrets: EnvironmentSecrets(values: [Self.name("token"): "s3cret"], unreadable: []), name: "Staging")
        let plan = Self.plan(data)
        let environment = try #require(plan.environments.first)
        #expect(plan.environments.count == 1)
        #expect(plan.collections.isEmpty && plan.globals.isEmpty && plan.notes == [])
        #expect(environment.name == "Staging")
        #expect(environment.variables.map(\.entry) == entries)
        #expect(environment.variables[2].value == .secret("s3cret"))
        #expect(environment.variables[3].value == .secret(""))
    }

    @Test func `two Environment exports with the same arguments are byte-equal and end in a newline`() {
        let entries = [VariableEntry(name: Self.name("a"), value: .plain("1"))]
        let data = Self.exportEnvironment(entries)
        #expect(data == Self.exportEnvironment(entries))
        #expect(data.last == UInt8(ascii: "\n"))
    }

    @Test(.enabled(if: PostmanExporterTests.hasSampleEnvironment))
    func `the example Environment exports and reads back to the same 14 Variables`() throws {
        let first = try #require(Self.plan(try Data(contentsOf: Self.sampleEnvironment)).environments.first)
        let entries = first.variables.map(\.entry)
        let again = try #require(Self.plan(Self.exportEnvironment(entries, secrets: .none, name: first.name)).environments.first)
        #expect(first.variables.count == 14)
        #expect(again.variables.map(\.entry) == entries)
    }
}

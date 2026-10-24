import Foundation
import RaccoonDomain
import Testing

struct PostmanMappingTests {
    /// RequestID n: the plan's ids, counted from 1 in plan order.
    static func id(_ n: Int) -> RequestID {
        RequestID(UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", n))!)
    }

    func plan(_ files: [PostmanFile], collections: [String] = [], globals: [VariableEntry] = [], environments: [String] = []) -> ImportPlan {
        var next = 0
        return PostmanMapping.plan(
            files, dataFolder: DataFolderIndex(collections.map { Collection(name: $0, nodes: []) }), globals: Globals(entries: globals),
            environments: environments.map { Environment(name: $0, entries: []) }
        ) {
            next += 1
            return Self.id(next)
        }
    }

    func plan(_ items: [PostmanItem], auth: PostmanAuth? = nil, events: [PostmanEvent] = [], description: String? = nil) -> ImportPlan {
        plan([.collection(PostmanCollection(name: "C", description: description, items: items, auth: auth, events: events))])
    }

    /// The one Request a Collection of `request` plans.
    func definition(_ request: PostmanRequest, auth: PostmanAuth? = nil) -> RequestDefinition? {
        guard case .request(let planned)? = plan([.request(request)], auth: auth).collections.first?.nodes.first else { return nil }
        return planned.definition
    }

    func notes(_ request: PostmanRequest) -> [ImportNote] {
        plan([.request(request)]).notes
    }

    func row(_ name: String, _ value: String, _ isEnabled: Bool = true) -> Row {
        Row(name: name, value: value, isEnabled: isEnabled)
    }

    /// What every planned Request starts from: Postman's default follows redirects.
    static let get = RequestDefinition(
        method: "GET", url: "", params: [], headers: [], cookies: [], body: .none, auth: .none,
        settings: RequestSettings(allowsInsecureTLS: false, followsRedirects: true)
    )

    @Test func `items become Folders and Requests in order, each with a new RequestID`() {
        let items: [PostmanItem] = [
            .request(PostmanRequest(name: "b", method: "post")),
            .folder(PostmanFolder(name: "F", items: [
                .folder(PostmanFolder(name: "Deep", items: [.request(PostmanRequest(name: "c"))])),
                .request(PostmanRequest(name: "a")),
            ])),
        ]
        var post = Self.get
        post.method = "POST"
        #expect(plan(items) == ImportPlan(collections: [ImportCollection(name: "C", nodes: [
            .request(Request(id: Self.id(1), name: "b", definition: post)),
            .folder(name: "F", children: [
                .folder(name: "Deep", children: [.request(Request(id: Self.id(2), name: "c", definition: Self.get))]),
                .request(Request(id: Self.id(3), name: "a", definition: Self.get)),
            ]),
        ])], environments: [], globals: [], notes: []))
    }
}

extension PostmanMappingTests {
    @Test(arguments: [
        ([PostmanItem.other(name: "x")], [String](), ["x"]),
        ([.request(PostmanRequest(name: "r")), .other(name: "x"), .folder(PostmanFolder(name: "F", items: [.other(name: "y")]))], ["r"], ["x", "y"]),
    ])
    func `an item with neither item nor request is skipped and counted`(items: [PostmanItem], planned: [String], skipped: [String]) {
        let plan = plan(items)
        func names(_ nodes: [ImportNode]) -> [String] {
            nodes.flatMap { node -> [String] in
                switch node {
                case .folder(_, let children): names(children)
                case .request(let request): [request.name]
                }
            }
        }
        #expect(names(plan.collections[0].nodes) == planned)
        #expect(plan.notes == [ImportNote(.itemsSkipped, names: skipped)])
    }
}

extension PostmanMappingTests {
    @Test(arguments: [
        // A string: the query is split as the URL bar splits it; {{name}} is unchanged.
        (PostmanURL(raw: "https://{{host}}/users?page=2&q=a%20b"), "https://{{host}}/users", [Row(name: "page", value: "2"), Row(name: "q", value: "a b")]),
        // An object: `raw` is the url, Params come from `query`, a disabled one stays as a Disabled Row.
        (
            PostmanURL(raw: "{{base}}/users?page=2#top", host: ["{{base}}"], path: ["users"],
                       query: [PostmanKeyValue(key: "page", value: "2"), PostmanKeyValue(key: "old", value: "1", disabled: true)], hash: "top"),
            "{{base}}/users", [Row(name: "page", value: "2"), Row(name: "old", value: "1", isEnabled: false)]
        ),
        // No `raw`: built from the parts.
        (
            PostmanURL(protocol: "https", host: ["api", "example", "com"], port: "8080", path: ["v1", "users"], query: [PostmanKeyValue(key: "a", value: "1")]),
            "https://api.example.com:8080/v1/users", [Row(name: "a", value: "1")]
        ),
        (PostmanURL(host: ["{{base}}"]), "{{base}}", []),
        (PostmanURL(), "", []),
    ])
    func `a url, a string or an object, becomes url without the query plus Params`(url: PostmanURL, expected: String, params: [Row]) {
        let definition = definition(PostmanRequest(name: "r", url: url))
        #expect(definition?.url == expected)
        #expect(definition?.params == params)
    }

    @Test(arguments: [
        (
            PostmanURL(raw: "https://h:8080/users/:id/posts/:post", variable: [PostmanKeyValue(key: "id", value: "7"), PostmanKeyValue(key: "post", value: "{{p}}")]),
            "https://h:8080/users/7/posts/{{p}}", [ImportNote(.pathVariable, names: ["r"])]
        ),
        (
            PostmanURL(host: ["h"], path: ["users", ":id", ":other"], variable: [PostmanKeyValue(key: "id", value: "")]),
            "h/users/:id/:other", [ImportNote(.pathVariableEmpty(name: "id"), names: ["r"]), ImportNote(.pathVariableEmpty(name: "other"), names: ["r"])]
        ),
        (PostmanURL(raw: "http://h/a:b/:x?y=:z", variable: [PostmanKeyValue(key: "x", value: "1")]), "http://h/a:b/1", [ImportNote(.pathVariable, names: ["r"])]),
    ])
    func `a path variable's value is written into the path, and an empty one keeps :name and is noted`(url: PostmanURL, expected: String, notes: [ImportNote]) {
        let request = PostmanRequest(name: "r", url: url)
        #expect(definition(request)?.url == expected)
        #expect(self.notes(request) == notes)
    }
}

extension PostmanMappingTests {
    @Test(arguments: [
        ([PostmanKeyValue(key: "Accept", value: "*/*"), PostmanKeyValue(key: "X-Old", value: "1", disabled: true)],
         [Row(name: "Accept", value: "*/*"), Row(name: "X-Old", value: "1", isEnabled: false)], [Row]()),
        ([PostmanKeyValue(key: "cookie", value: "a=1; b={{t}}"), PostmanKeyValue(key: "X", value: "y"), PostmanKeyValue(key: "Cookie", value: "c=3", disabled: true)],
         [Row(name: "X", value: "y")], [Row(name: "a", value: "1"), Row(name: "b", value: "{{t}}"), Row(name: "c", value: "3", isEnabled: false)]),
    ])
    func `headers carry over, Disabled Rows included, and a Cookie header becomes Request Cookies`(headers: [PostmanKeyValue], expected: [Row], cookies: [Row]) {
        let definition = definition(PostmanRequest(name: "r", headers: headers))
        #expect(definition?.headers == expected)
        #expect(definition?.cookies == cookies)
    }
}

extension PostmanMappingTests {
    @Test(arguments: [
        (PostmanBody.raw(#"{"a": 1}"#, language: "json"), Body.raw(.json, #"{"a": 1}"#)),
        (.raw("<a/>", language: "xml"), .raw(.xml, "<a/>")),
        (.raw("hi", language: "text"), .raw(.text, "hi")),
        (.raw("<p/>", language: "html"), .raw(.text, "<p/>")),
        (.raw("x()", language: "javascript"), .raw(.text, "x()")),
        (.raw("hi", language: nil), .raw(.text, "hi")),
        (.urlencoded([PostmanKeyValue(key: "a", value: "1"), PostmanKeyValue(key: "b", value: "2", disabled: true)]),
         .formURLEncoded([Row(name: "a", value: "1"), Row(name: "b", value: "2", isEnabled: false)])),
        (.formdata([
            PostmanFormParameter(key: "t", content: .text("v")),
            PostmanFormParameter(key: "f", content: .file(src: ["/Users/me/a.png", "/tmp/b.png"]), disabled: true),
         ]),
         .multipart([
            Part(name: "t", content: .text("v")),
            Part(name: "f", isEnabled: false, content: .file(path: "/Users/me/a.png")),
            Part(name: "f", isEnabled: false, content: .file(path: "/tmp/b.png")),
         ])),
        (.graphql(query: "{ me }", variables: #"{"a": 1}"#), .raw(.json, #"{"query":"{ me }","variables":{"a": 1}}"#)),
        (.graphql(query: "{ me }", variables: " "), .raw(.json, #"{"query":"{ me }"}"#)),
        (.file(src: "/tmp/a.bin"), .none),
        // Nothing in it sends no bytes: Postman exports these on plain GETs.
        (.raw("", language: "json"), .none),
        (.urlencoded([]), .none),
        (.formdata([]), .none),
        (.graphql(query: "", variables: ""), .none),
    ])
    func `every body kind maps`(body: PostmanBody, expected: Body) {
        #expect(definition(PostmanRequest(name: "r", body: body))?.body == expected)
    }

    @Test(arguments: [
        (PostmanBody.file(src: "/tmp/a.bin"), [ImportNote(.binaryBody, names: ["r"])]),
        (.formdata([
            PostmanFormParameter(key: "a", content: .file(src: ["a.png"])),
            PostmanFormParameter(key: "b", content: .file(src: [])),
            PostmanFormParameter(key: "c", content: .file(src: ["/abs/c.png"])),
         ]),
         [ImportNote(.fileOnlyName(path: "a.png"), names: ["r"]), ImportNote(.fileOnlyName(path: ""), names: ["r"])]),
    ])
    func `a binary body and a file part with only a name are noted`(body: PostmanBody, notes: [ImportNote]) {
        #expect(self.notes(PostmanRequest(name: "r", body: body)) == notes)
    }
}

extension PostmanMappingTests {
    @Test(arguments: [
        (PostmanBody.raw("{}", language: "json"), [PostmanKeyValue](), [Row(name: "Content-Type", value: "application/json")]),
        (.raw("<a/>", language: "xml"), [], [Row(name: "Content-Type", value: "application/xml")]),
        (.urlencoded([PostmanKeyValue(key: "a", value: "1")]), [], [Row(name: "Content-Type", value: "application/x-www-form-urlencoded")]),
        (.formdata([PostmanFormParameter(key: "a", content: .text("1"))]), [], [Row(name: "Content-Type", value: "multipart/form-data")]),
        (.graphql(query: "{ me }", variables: ""), [], [Row(name: "Content-Type", value: "application/json")]),
        // The request has one, of any case, enabled or not: it is kept as it is.
        (.raw("{}", language: "json"), [PostmanKeyValue(key: "content-type", value: "application/vnd.api+json")],
         [Row(name: "content-type", value: "application/vnd.api+json")]),
        (.raw("{}", language: "json"), [PostmanKeyValue(key: "Content-Type", value: "text/plain", disabled: true)],
         [Row(name: "Content-Type", value: "text/plain", isEnabled: false)]),
        // No body, no header.
        (.raw("", language: "json"), [], []),
        (.file(src: "/a.bin"), [], []),
    ])
    func `a body Content-Type is added only when the request has none`(body: PostmanBody, headers: [PostmanKeyValue], expected: [Row]) {
        #expect(definition(PostmanRequest(name: "r", headers: headers, body: body))?.headers == expected)
    }
}

extension PostmanMappingTests {
    @Test(arguments: [
        (PostmanAuth(type: "noauth"), Auth.none),
        (PostmanAuth(type: "basic", parameters: ["username": "u", "password": "{{p}}"]), .basic(user: "u", password: "{{p}}")),
        (PostmanAuth(type: "basic"), .basic(user: "", password: "")),
        (PostmanAuth(type: "bearer", parameters: ["token": "t0k"]), .bearer(token: "t0k")),
    ])
    func `noauth, basic and bearer map to Auth`(auth: PostmanAuth, expected: Auth) {
        #expect(definition(PostmanRequest(name: "r", auth: auth))?.auth == expected)
        #expect(notes(PostmanRequest(name: "r", auth: auth)) == [])
    }

    @Test(arguments: [
        (PostmanAuth(type: "apikey", parameters: ["key": "X-Key", "value": "k", "in": "header"]), [Row(name: "X-Key", value: "k")], [Row]()),
        (PostmanAuth(type: "apikey", parameters: ["key": "X-Key", "value": "k"]), [Row(name: "X-Key", value: "k")], []),
        (PostmanAuth(type: "apikey", parameters: ["key": "api_key", "value": "k", "in": "query"]), [], [Row(name: "page", value: "1"), Row(name: "api_key", value: "k")]),
    ])
    func `apikey becomes a header or a Param with that name and value`(auth: PostmanAuth, headers: [Row], params: [Row]) {
        let request = PostmanRequest(name: "r", url: PostmanURL(raw: "http://h/?page=1"), auth: auth)
        let definition = definition(request)
        #expect(definition?.auth == Auth.none)
        #expect(definition?.headers == headers)
        #expect(definition?.params == (params.isEmpty ? [Row(name: "page", value: "1")] : params))
    }

    @Test(arguments: ["oauth2", "oauth1", "digest", "awsv4", "ntlm", "jwt", "hawk", "akamai", "edgegrid"])
    func `an auth Raccoon does not support is none, noted per Request`(type: String) {
        let request = PostmanRequest(name: "r", auth: PostmanAuth(type: type, parameters: ["a": "b"]))
        #expect(definition(request)?.auth == Auth.none)
        #expect(notes(request) == [ImportNote(.authNotSupported(type: type), names: ["r"])])
    }

    @Test func `inherited auth is the nearest Folder's or the Collection's, copied onto the Request`() {
        let bearer = PostmanAuth(type: "bearer", parameters: ["token": "c"])
        let plan = plan([
            .request(PostmanRequest(name: "fromCollection")),
            .request(PostmanRequest(name: "explicitInherit", auth: PostmanAuth(type: "inherit"))),
            .request(PostmanRequest(name: "own", auth: PostmanAuth(type: "basic", parameters: ["username": "u"]))),
            .folder(PostmanFolder(name: "F", items: [
                .request(PostmanRequest(name: "fromFolder")),
                .folder(PostmanFolder(name: "G", items: [.request(PostmanRequest(name: "fromGrandparent"))], auth: PostmanAuth(type: "inherit"))),
            ], auth: PostmanAuth(type: "apikey", parameters: ["key": "K", "value": "v"]))),
            .folder(PostmanFolder(name: "None", items: [.request(PostmanRequest(name: "noauth"))], auth: PostmanAuth(type: "noauth"))),
            .folder(PostmanFolder(name: "Odd", items: [.request(PostmanRequest(name: "digest"))], auth: PostmanAuth(type: "digest"))),
        ], auth: bearer)
        var requests: [String: RequestDefinition] = [:]
        func walk(_ nodes: [ImportNode]) {
            for node in nodes {
                switch node {
                case .folder(_, let children): walk(children)
                case .request(let request): requests[request.name] = request.definition
                }
            }
        }
        walk(plan.collections[0].nodes)
        #expect(requests["fromCollection"]?.auth == .bearer(token: "c"))
        #expect(requests["explicitInherit"]?.auth == .bearer(token: "c"))
        #expect(requests["own"]?.auth == .basic(user: "u", password: ""))
        #expect(requests["fromFolder"]?.headers == [Row(name: "K", value: "v")])
        #expect(requests["fromGrandparent"]?.headers == [Row(name: "K", value: "v")])
        #expect(requests["noauth"]?.auth == Auth.none)
        #expect(requests["digest"]?.auth == Auth.none)
        #expect(plan.notes == [
            ImportNote(.authInherited, names: ["fromCollection", "explicitInherit", "fromFolder", "fromGrandparent", "digest"]),
            ImportNote(.authNotSupported(type: "digest"), names: ["digest"]),
        ])
    }

    @Test func `with no auth anywhere, a Request has none and nothing is noted`() {
        #expect(plan([.request(PostmanRequest(name: "r"))], auth: PostmanAuth(type: "inherit")).notes == [])
    }
}

extension PostmanMappingTests {
    @Test(arguments: [
        (Bool?.none, Bool?.none, RequestSettings(allowsInsecureTLS: false, followsRedirects: true)),
        (false, nil, RequestSettings(allowsInsecureTLS: false, followsRedirects: false)),
        (true, true, RequestSettings(allowsInsecureTLS: false, followsRedirects: true)),
        (nil, false, RequestSettings(allowsInsecureTLS: true, followsRedirects: true)),
    ])
    func `protocolProfileBehavior becomes Request Settings, following redirects by default as Postman does`(followRedirects: Bool?, strictSSL: Bool?, expected: RequestSettings) {
        #expect(definition(PostmanRequest(name: "r", followRedirects: followRedirects, strictSSL: strictSSL))?.settings == expected)
    }
}

extension PostmanMappingTests {
    static let script = PostmanEvent(listen: "prerequest", exec: "pm.environment.set('a', 1)")
    static let blank = PostmanEvent(listen: "test", exec: " \n")

    @Test func `scripts are dropped and counted, a Folder's or the Collection's on every Request under it, blank ones not`() {
        let plan = plan([
            .request(PostmanRequest(name: "own", events: [Self.script])),
            .request(PostmanRequest(name: "blank", events: [Self.blank])),
            .folder(PostmanFolder(name: "F", items: [.request(PostmanRequest(name: "underFolder"))], events: [Self.script])),
            .folder(PostmanFolder(name: "G", items: [.request(PostmanRequest(name: "underBlank"))], events: [Self.blank])),
        ])
        #expect(plan.notes == [ImportNote(.scriptsDropped, names: ["own", "underFolder"])])
        let underCollection = self.plan([.request(PostmanRequest(name: "r"))], events: [Self.script])
        #expect(underCollection.notes == [ImportNote(.scriptsDropped, names: ["r"])])
    }

    @Test(arguments: [
        (PostmanRequest(name: "r", responseCount: 2), [ImportNote(.examplesDropped, names: ["r"])]),
        (PostmanRequest(name: "r", description: "Lists users."), [ImportNote(.descriptionsDropped, names: ["r"])]),
        (PostmanRequest(name: "r", description: ""), []),
    ])
    func `saved examples and descriptions are dropped and counted`(request: PostmanRequest, notes: [ImportNote]) {
        #expect(self.notes(request) == notes)
    }

    @Test func `a Folder's and the Collection's description are named by that Folder and Collection`() {
        let plan = plan([.folder(PostmanFolder(name: "F", description: "About F", items: []))], description: "About C")
        #expect(plan.notes == [ImportNote(.descriptionsDropped, names: ["C", "F"])])
    }

    @Test(arguments: [
        (PostmanRequest(name: "r", url: PostmanURL(raw: "http://h/{{$guid}}?t={{ $timestamp }}")),
         [ImportNote(.dynamicVariable(name: "$guid"), names: ["r"]), ImportNote(.dynamicVariable(name: "$timestamp"), names: ["r"])]),
        (PostmanRequest(name: "r", headers: [PostmanKeyValue(key: "X-Id", value: "{{$randomUUID}}"), PostmanKeyValue(key: "Cookie", value: "n={{$randomInt}}")]),
         [ImportNote(.dynamicVariable(name: "$randomUUID"), names: ["r"]), ImportNote(.dynamicVariable(name: "$randomInt"), names: ["r"])]),
        (PostmanRequest(name: "r", body: .raw(#"{"id": "{{$guid}}", "n": "{{$guid}}"}"#, language: "json")),
         [ImportNote(.dynamicVariable(name: "$guid"), names: ["r"])]),
        (PostmanRequest(name: "r", auth: PostmanAuth(type: "bearer", parameters: ["token": "{{$randomPassword}}"])),
         [ImportNote(.dynamicVariable(name: "$randomPassword"), names: ["r"])]),
        (PostmanRequest(name: "r", url: PostmanURL(raw: "http://h/{{guid}}")), []),
    ])
    func `dynamic variables are left as typed and noted`(request: PostmanRequest, notes: [ImportNote]) {
        #expect(definition(request)?.url == URLText.split(request.url.raw ?? "").base)
        #expect(self.notes(request) == notes)
    }

    @Test func `a loss is one note with a count and the Requests it applies to, across Collections`() {
        let binary = PostmanBody.file(src: "a.bin")
        let plan = plan([
            .collection(PostmanCollection(name: "A", items: [
                .request(PostmanRequest(name: "Upload", body: binary)),
                .request(PostmanRequest(name: "Login", auth: PostmanAuth(type: "oauth2"))),
            ])),
            .notPostman,
            .collection(PostmanCollection(name: "B", items: [
                .folder(PostmanFolder(name: "F", items: [.request(PostmanRequest(name: "Upload", body: binary))])),
            ])),
        ])
        #expect(plan.collections.map(\.name) == ["A", "B"])
        #expect(plan.notes == [
            ImportNote(.binaryBody, names: ["Upload", "Upload"]),
            ImportNote(.authNotSupported(type: "oauth2"), names: ["Login"]),
        ])
        #expect(plan.notes.map(\.names.count) == [2, 1])
    }
}

extension PostmanMappingTests {
    @Test(arguments: [
        ([String](), ["Prod"], ["Prod"], [ImportNote]()),
        (["prod"], ["Prod"], ["Prod 2"], [ImportNote(.renamed(from: "Prod", to: "Prod 2"), names: ["Prod"])]),
        ([], ["Prod", "Prod"], ["Prod", "Prod 2"], [ImportNote(.renamed(from: "Prod", to: "Prod 2"), names: ["Prod"])]),
        ([], ["a/b"], ["a-b"], [ImportNote(.renamed(from: "a/b", to: "a-b"), names: ["a/b"])]),
    ])
    func `a taken Environment name is planned as name 2 and noted, since Import never overwrites`(
        taken: [String], imported: [String], planned: [String], notes: [ImportNote]
    ) {
        let plan = plan(imported.map { .environment(PostmanEnvironment(name: $0, values: [])) }, environments: taken)
        #expect(plan.environments.map(\.name) == planned)
        #expect(plan.notes == notes)
    }
}

extension PostmanMappingTests {
    @Test func `a taken Collection name is planned as name 2 and noted, the Collections and Environments taken apart`() {
        let plan = plan([
            .collection(PostmanCollection(name: "Payments", items: [])),
            .environment(PostmanEnvironment(name: "Payments", values: [])),
            .collection(PostmanCollection(name: "Payments", items: [])),
        ], collections: ["payments"])
        #expect(plan.collections.map(\.name) == ["Payments 2", "Payments 3"])
        #expect(plan.environments.map(\.name) == ["Payments"])
        #expect(plan.notes == [
            ImportNote(.renamed(from: "Payments", to: "Payments 2"), names: ["Payments"]),
            ImportNote(.renamed(from: "Payments", to: "Payments 3"), names: ["Payments"]),
        ])
    }
}

extension PostmanMappingTests {
    static func name(_ text: String) -> VariableName { VariableName(text)! }

    @Test(arguments: [
        (PostmanVariable(key: "host", value: "api.example.com"), [ImportVariable(name: name("host"), value: .plain("api.example.com"))], [ImportNote]()),
        (PostmanVariable(key: "old", value: "1", enabled: false), [ImportVariable(name: name("old"), isEnabled: false, value: .plain("1"))], []),
        (PostmanVariable(key: "token", value: "s3cr3t", type: "secret"), [ImportVariable(name: name("token"), value: .secret("s3cr3t"))], []),
        (PostmanVariable(key: "k", value: "v", type: "default"), [ImportVariable(name: name("k"), value: .plain("v"))], []),
        (PostmanVariable(key: " padded ", value: "v"), [ImportVariable(name: name("padded"), value: .plain("v"))], []),
        (PostmanVariable(key: "base url", value: "v"), [], [ImportNote(.variableNameInvalid, names: ["base url"])]),
        (PostmanVariable(key: "", value: ""), [], []),
    ])
    func `Environment values become its Variables, disabled kept disabled, a secret a Secret Variable`(
        value: PostmanVariable, variables: [ImportVariable], notes: [ImportNote]
    ) {
        let plan = plan([.environment(PostmanEnvironment(name: "Dev", values: [value]))])
        #expect(plan.environments == [ImportEnvironment(name: "Dev", variables: variables)])
        #expect(plan.notes == notes)
    }

    @Test func `a secret is planned for the Keychain and never with its value in the file`() throws {
        let plan = plan([.environment(PostmanEnvironment(name: "Prod", values: [PostmanVariable(key: "token", value: "s3cr3t", type: "secret")]))])
        let token = try #require(plan.environments.first?.variables.first)
        #expect(token.value == .secret("s3cr3t"))
        #expect(token.entry == VariableEntry(name: Self.name("token"), value: .secret))
        let file = String(decoding: EnvironmentFile.encode([token.entry]), as: UTF8.self)
        #expect(!file.contains("s3cr3t"))
    }
}

extension PostmanMappingTests {
    static let host = PostmanVariable(key: "host", value: "postman.example.com")
    static let key = PostmanVariable(key: "key", value: "k", type: "secret")

    @Test(arguments: [
        ([VariableEntry](), [ImportVariable(name: name("host"), value: .plain("postman.example.com")), ImportVariable(name: name("key"), value: .secret("k"))], [ImportNote]()),
        ([VariableEntry(name: name("host"), value: .plain("raccoon.example.com"))], [ImportVariable(name: name("key"), value: .secret("k"))],
         [ImportNote(.globalSkipped, names: ["host"])]),
        ([VariableEntry(name: name("host"), value: .secret), VariableEntry(name: name("key"), isEnabled: false, value: .plain(""))], [],
         [ImportNote(.globalSkipped, names: ["host", "key"])]),
    ])
    func `Globals keep the names they have and list the imported ones as skipped`(existing: [VariableEntry], added: [ImportVariable], notes: [ImportNote]) {
        let plan = plan([.globals([Self.host, Self.key])], globals: existing)
        #expect(plan.globals == added)
        #expect(plan.notes == notes)
    }

    @Test func `Collection variables are added to Globals before Globals files, so a Collection variable wins as in Postman`() {
        let plan = plan([
            .globals([PostmanVariable(key: "host", value: "global.example.com"), PostmanVariable(key: "page", value: "1")]),
            .collection(PostmanCollection(name: "A", items: [], variables: [Self.host, PostmanVariable(key: "off", value: "x", enabled: false)])),
            .collection(PostmanCollection(name: "B", items: [], variables: [PostmanVariable(key: "host", value: "b.example.com")])),
            .collection(PostmanCollection(name: "C", items: [])),
        ])
        #expect(plan.globals == [
            ImportVariable(name: Self.name("host"), value: .plain("postman.example.com")),
            ImportVariable(name: Self.name("off"), isEnabled: false, value: .plain("x")),
            ImportVariable(name: Self.name("page"), value: .plain("1")),
        ])
        #expect(plan.notes == [ImportNote(.collectionVariables, names: ["A"]), ImportNote(.globalSkipped, names: ["host", "host"])])
    }
}

extension PostmanMappingTests {
    @Test(arguments: [
        ("", "{{base}}/users/42?verbose=1", "POST", "/users/42"),
        ("  ", "https://api.example.com", "GET", "https://api.example.com"),
        ("", "", "DELETE", "DELETE"),
        ("Login", "https://h/login", "POST", "Login"),
    ])
    func `a Request with no name is named as its Draft Tab would be titled, else by its method`(name: String, url: String, method: String, planned: String) {
        let plan = plan([.request(PostmanRequest(name: name, method: method, url: PostmanURL(raw: url), responseCount: 1))])
        guard case .request(let request)? = plan.collections.first?.nodes.first else { Issue.record("no Request planned"); return }
        #expect(request.name == planned)
        #expect(plan.notes == [ImportNote(.examplesDropped, names: [planned])])
    }
}

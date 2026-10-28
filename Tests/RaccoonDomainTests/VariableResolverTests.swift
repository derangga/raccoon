import Foundation
import RaccoonDomain
import Testing

struct VariableResolverTests {
    func definition(_ method: String, _ url: String) -> RequestDefinition {
        var definition = RequestDefinition.empty
        definition.method = method
        definition.url = url
        return definition
    }

    @Test(arguments: [
        ("GET", "http://localhost:8080/", "http://localhost:8080/"),
        ("POST", "https://api.example.com/users", "https://api.example.com/users"),
    ])
    func `a method and a URL resolve into the URL the transport sends`(method: String, text: String, url: String) throws {
        let resolved = try VariableResolver.resolve(definition(method, text))

        #expect(resolved.url == URL(string: url))
        #expect(resolved.definition.method == method)
    }

    @Test(arguments: ["", "not a url", "localhost:8080", "http://"])
    func `a URL that cannot be built is not sent and the error quotes it`(text: String) {
        #expect(throws: ResolveError.invalidURL(text)) {
            try VariableResolver.resolve(definition("GET", text))
        }
    }

    @Test func `Disabled Rows are dropped from params, headers, cookies, form and multipart`() throws {
        let on = Row(name: "on", value: "1"), off = Row(name: "off", value: "0", isEnabled: false)
        var form = definition("POST", "http://h/")
        form.params = [off, on]
        form.headers = [on, off]
        form.cookies = [off, on]
        form.body = .formURLEncoded([on, off])
        var multipart = form
        multipart.body = .multipart([
            Part(name: "a", content: .text("x")),
            Part(name: "b", isEnabled: false, content: .file(path: "/tmp/b")),
            Part(name: "c", content: .file(path: "/tmp/c")),
        ])

        let resolvedForm = try VariableResolver.resolve(form).definition
        #expect(resolvedForm.params == [on])
        #expect(resolvedForm.headers == [on])
        #expect(resolvedForm.cookies == [on])
        #expect(resolvedForm.body == .formURLEncoded([on]))
        #expect(try VariableResolver.resolve(multipart).definition.body == .multipart([
            Part(name: "a", content: .text("x")),
            Part(name: "c", content: .file(path: "/tmp/c")),
        ]))
    }

    @Test(arguments: [
        ([Row(name: "q", value: "a&b")], "http://h/search?q=a%26b"),
        ([Row(name: "q", value: "a b"), Row(name: "n", value: "1+1=2")], "http://h/search?q=a%20b&n=1+1=2"),
        ([Row(name: "off", value: "x", isEnabled: false)], "http://h/search"),
        ([Row(name: "a b", value: "")], "http://h/search?a%20b="),
    ])
    func `params are percent-encoded once into the URL`(params: [Row], url: String) throws {
        var request = definition("GET", "http://h/search")
        request.params = params

        #expect(try VariableResolver.resolve(request).url.absoluteString == url)
    }

    @Test(arguments: [
        (Auth.basic(user: "aladdin", password: "opensesame"), "Basic YWxhZGRpbjpvcGVuc2VzYW1l"),
        (Auth.bearer(token: "abc.def"), "Bearer abc.def"),
    ])
    func `Auth becomes an Authorization header after the user's headers`(auth: Auth, value: String) throws {
        var request = definition("GET", "http://h/")
        request.headers = [Row(name: "Accept", value: "*/*")]
        request.auth = auth

        let resolved = try VariableResolver.resolve(request).definition
        #expect(resolved.headers == [Row(name: "Accept", value: "*/*"), Row(name: "Authorization", value: value)])
        #expect(resolved.auth == .none)
    }

    @Test(arguments: [
        ([Row(name: "Authorization", value: "Basic eHl6")], [Row(name: "Authorization", value: "Basic eHl6")]),
        ([Row(name: "authorization", value: "Bearer x")], [Row(name: "authorization", value: "Bearer x")]),
        ([Row(name: "AUTHORIZATION", value: "")], [Row(name: "AUTHORIZATION", value: "")]),
        ([Row(name: "Authorization", value: "Basic eHl6", isEnabled: false)], [Row(name: "Authorization", value: "Bearer abc")]),
        ([Row(name: "Accept", value: "*/*")], [Row(name: "Accept", value: "*/*"), Row(name: "Authorization", value: "Bearer abc")]),
    ])
    func `an enabled Authorization row wins over Auth's header, a disabled one does not`(headers: [Row], sent: [Row]) throws {
        var request = definition("GET", "http://h/")
        request.headers = headers
        request.auth = .bearer(token: "abc")

        #expect(try VariableResolver.resolve(request).definition.headers == sent)
    }

    @Test func `no Auth adds no header`() throws {
        #expect(try VariableResolver.resolve(definition("GET", "http://h/")).definition.headers.isEmpty)
    }

    // MARK: Variables

    func name(_ text: String) -> VariableName { VariableName(text)! }
    func plain(_ text: String, _ value: String, enabled: Bool = true) -> VariableEntry {
        VariableEntry(name: name(text), isEnabled: enabled, value: .plain(value))
    }

    func scope(_ values: [String: String]) -> VariableScope {
        VariableScope(values: Dictionary(uniqueKeysWithValues: values.map { (name($0.key), $0.value) }))
    }

    static let precedence: [([VariableEntry], [VariableEntry]?, [String: String])] = {
        func entry(_ name: String, _ value: String, _ enabled: Bool = true) -> VariableEntry {
            VariableEntry(name: VariableName(name)!, isEnabled: enabled, value: .plain(value))
        }
        return [
            ([entry("host", "global")], nil, ["host": "global"]),
            ([entry("host", "global")], [entry("host", "dev")], ["host": "dev"]),
            ([entry("host", "global"), entry("a", "1")], [entry("b", "2")], ["host": "global", "a": "1", "b": "2"]),
            ([entry("host", "global", false)], [], [:]),
            ([entry("host", "global")], [entry("host", "dev", false)], ["host": "global"]),
        ]
    }()

    @Test(arguments: precedence)
    func `the Active Environment overrides Globals by name, and disabled entries count for nothing`(
        globals: [VariableEntry], active: [VariableEntry]?, expected: [String: String]
    ) {
        let scope = VariableScope(active: active.map { Environment(name: "Dev", entries: $0) }, globals: Globals(entries: globals), secrets: [:])

        #expect(scope == self.scope(expected))
    }

    @Test func `a secret takes its value from the dictionary, and one the Keychain did not give is undefined`() throws {
        let globals = Globals(entries: [plain("token", "dev-token"), VariableEntry(name: name("key"), value: .secret)])
        let prod = Environment(name: "Prod", entries: [VariableEntry(name: name("token"), value: .secret)])
        var request = definition("GET", "http://h/")
        request.auth = .bearer(token: "{{token}}")

        let read = VariableScope(active: prod, globals: globals, secrets: [name("token"): "prod-token", name("key"): "k"])
        #expect(read == scope(["token": "prod-token", "key": "k"]))
        #expect(try VariableResolver.resolve(request, scope: read).definition.headers == [Row(name: "Authorization", value: "Bearer prod-token")])

        // Unreadable: the Prod secret does not fall back to the Globals one.
        let unread = VariableScope(active: prod, globals: globals, secrets: [:])
        #expect(throws: ResolveError.undefined([name("token")])) {
            try VariableResolver.resolve(request, scope: unread)
        }
    }

    @Test func `every field that takes Variables is substituted`() throws {
        var request = definition("POST", "{{base}}/users")
        request.params = [Row(name: "{{p}}", value: "{{v}}")]
        request.headers = [Row(name: "X-Key", value: "k {{v}} k")]
        request.cookies = [Row(name: "session", value: "{{ v }}")]
        request.body = .raw(.json, #"{"id": "{{v}}"}"#)
        request.auth = .basic(user: "{{user}}", password: "{{v}}")
        let scope = scope(["base": "https://api.example.com", "p": "page", "v": "2", "user": "ada"])

        let resolved = try VariableResolver.resolve(request, scope: scope)

        #expect(resolved.url.absoluteString == "https://api.example.com/users?page=2")
        #expect(resolved.definition.headers == [
            Row(name: "X-Key", value: "k 2 k"),
            Row(name: "Authorization", value: "Basic \(Data("ada:2".utf8).base64EncodedString())"),
        ])
        #expect(resolved.definition.cookies == [Row(name: "session", value: "2")])
        #expect(resolved.definition.body == .raw(.json, #"{"id": "2"}"#))

        request.body = .formURLEncoded([Row(name: "{{p}}", value: "{{v}}")])
        #expect(try VariableResolver.resolve(request, scope: scope).definition.body == .formURLEncoded([Row(name: "page", value: "2")]))
        request.body = .multipart([Part(name: "{{p}}", content: .text("{{v}}")), Part(name: "f", content: .file(path: "/tmp/{{v}}.png"))])
        #expect(try VariableResolver.resolve(request, scope: scope).definition.body == .multipart([
            Part(name: "page", content: .text("2")), Part(name: "f", content: .file(path: "/tmp/2.png")),
        ]))
        request.auth = .bearer(token: "{{v}}")
        #expect(try VariableResolver.resolve(request, scope: scope).definition.headers.last == Row(name: "Authorization", value: "Bearer 2"))
    }

    @Test func `every Undefined Variable is reported once, in the order they appear, not the first`() {
        var request = definition("GET", "{{base}}/users")
        request.headers = [Row(name: "X-A", value: "{{a}}"), Row(name: "X-Off", value: "{{off}}", isEnabled: false)]
        request.body = .raw(.text, "{{a}} {{c}} {{defined}}")
        request.auth = .bearer(token: "{{token}}")

        #expect(throws: ResolveError.undefined([name("base"), name("a"), name("c"), name("token")])) {
            try VariableResolver.resolve(request, scope: scope(["defined": "yes"]))
        }
    }

    @Test(arguments: [
        ("{{a}}", ["a": "{{b}}", "b": "x"], "{{b}}"),
        ("{{a}}{{a}}", ["a": "{{a}}"], "{{a}}{{a}}"),
        ("{{$guid}} {{a b}}", [:], "{{$guid}} {{a b}}"),
    ])
    func `substitution is one pass, not recursive, and leaves what is not a Variable`(text: String, values: [String: String], sent: String) throws {
        var request = definition("GET", "http://h/")
        request.headers = [Row(name: "X", value: text)]

        #expect(try VariableResolver.resolve(request, scope: scope(values)).definition.headers == [Row(name: "X", value: sent)])
    }

    @Test func `a value with & stays one param after substitution`() throws {
        var request = definition("GET", "http://h/search")
        request.params = [Row(name: "q", value: "{{q}}"), Row(name: "n", value: "1")]

        #expect(try VariableResolver.resolve(request, scope: scope(["q": "a&b=c"])).url.absoluteString == "http://h/search?q=a%26b=c&n=1")
    }

    // MARK: Path Variables

    @Test(arguments: [
        ("http://h/posts/:id/retry", ["id": "689eba19be47b88f9d590367"], [:], "http://h/posts/689eba19be47b88f9d590367/retry"),
        ("http://h/posts/:id/retry", [:], [:], "http://h/posts/:id/retry"),
        ("http://h/posts/:id/retry", ["id": ""], [:], "http://h/posts/:id/retry"),
        ("http://h/posts/:id", ["id": "{{user_id}}"], ["user_id": "u 1"], "http://h/posts/u%201"),
        ("http://h/posts/:id", ["id": "{{empty}}"], ["empty": ""], "http://h/posts/:id"),
        ("http://h/:{{x}}", [:], ["x": "val"], "http://h/:val"),
        ("http://h/:id/:id", ["id": "7"], [:], "http://h/7/7"),
        ("http://h/:id.json", ["id": "7"], [:], "http://h/7.json"),
        ("http://h/:id", ["id": "a/b"], [:], "http://h/a/b"),
        ("http://h/:id", ["id": "a%2Fb"], [:], "http://h/a%2Fb"),
        ("http://h/:id", ["id": "100%"], [:], "http://h/100%25"),
        ("http://h/:id", ["id": "a?b#c"], [:], "http://h/a%3Fb%23c"),
        ("http://h/:id", ["id": "{{other}}"], ["other": "/:other"], "http://h//:other"),
        ("{{base}}/:id", ["id": "7"], ["base": "http://h/:id"], "http://h/:id/7"),
        ("http://h/a#/:id", ["id": "7"], [:], "http://h/a#/:id"),
        ("http://localhost:3061/:id", ["id": "7"], [:], "http://localhost:3061/7"),
    ] as [(String, [String: String], [String: String], String)])
    func `a Path Variable's value replaces :name once, encoded as a path segment`(url: String, values: [String: String], scope values2: [String: String], sent: String) throws {
        var request = definition("GET", url)
        request.pathVariables = values
        #expect(try VariableResolver.resolve(request, scope: scope(values2)).url.absoluteString == sent)
    }

    @Test func `a Path Variable value and a header Undefined Variable are reported together, in order`() {
        var request = definition("GET", "http://h/:id/{{base}}")
        request.pathVariables = ["id": "{{missing}} {{base}}"]
        request.headers = [Row(name: "X", value: "{{token}}")]
        #expect(throws: ResolveError.undefined([name("missing"), name("base"), name("token")])) {
            try VariableResolver.resolve(request, scope: scope([:]))
        }
    }

    @Test func `a Variable whose value is /:other creates no Path Variable at send`() throws {
        var request = definition("GET", "http://h/:id")
        request.pathVariables = ["id": "{{o}}", "other": "ZZ"]
        #expect(try VariableResolver.resolve(request, scope: scope(["o": "/:other"])).url.absoluteString == "http://h//:other")
    }

    @Test func `a value of a name that is not in the URL is not sent and not scanned`() throws {
        var request = definition("GET", "http://h/x")
        request.pathVariables = ["gone": "{{missing}}"]
        #expect(try VariableResolver.resolve(request, scope: scope([:])).url.absoluteString == "http://h/x")
    }

    @Test func `a Path Variable's value does not reach the resolved definition's other fields`() throws {
        var request = definition("GET", "http://h/:id")
        request.pathVariables = ["id": "7"]
        #expect(try VariableResolver.resolve(request).definition.url == "http://h/7")
    }
}

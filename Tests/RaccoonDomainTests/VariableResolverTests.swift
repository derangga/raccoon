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

    @Test func `no Auth adds no header`() throws {
        #expect(try VariableResolver.resolve(definition("GET", "http://h/")).definition.headers.isEmpty)
    }
}

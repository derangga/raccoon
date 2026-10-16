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
}

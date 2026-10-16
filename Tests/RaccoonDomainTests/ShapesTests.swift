import RaccoonDomain
import Testing

struct ShapesTests {
    @Test(arguments: [
        ("token", true), ("api_key", true), ("base-url", true), ("v1.host", true), ("A9", true),
        ("", false), ("has space", false), ("{{token}}", false), ("$guid", false),
        ("ñame", false), ("a/b", false),
    ])
    func `VariableName accepts letters, digits, _, - and . only`(text: String, isValid: Bool) {
        #expect((VariableName(text) != nil) == isValid)
    }

    @Test func `the empty Draft is GET with nothing else`() {
        let emptyDraft = RequestDefinition(
            method: "GET", url: "", params: [], headers: [], cookies: [],
            body: .none, auth: .none,
            settings: RequestSettings(allowsInsecureTLS: false, followsRedirects: false, requestsCompression: false)
        )
        #expect(RequestDefinition.empty == emptyDraft)
    }
}

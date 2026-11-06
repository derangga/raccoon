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

    /// shapes.md: one clamp in the init covers the file, Postman Import, Curl Import and the pane.
    @Test(arguments: [(-1, 0), (0, 0), (10, 10), (20, 20), (21, 20), (1000, 20), (9_007_199_254_740_991, 20)])
    func `the Redirect Limit is clamped to 0 through 20`(set: Int, kept: Int) {
        #expect(RequestSettings(allowsInsecureTLS: false, followsRedirects: false, maxRedirects: set).maxRedirects == kept)
    }

    @Test(arguments: [(nil, nil), (0, 1), (1, 1), (60, 60), (3600, 3600), (9999, 3600)] as [(Int?, Int?)])
    func `the Request Timeout is nil or clamped to 1 through 3600`(set: Int?, kept: Int?) {
        #expect(RequestSettings(allowsInsecureTLS: false, followsRedirects: false, timeoutSeconds: set).timeoutSeconds == kept)
    }

    @Test func `the four new Request Settings default to off, 20 and no timeout`() {
        let settings = RequestDefinition.empty.settings
        #expect(settings.followsOriginalMethod == false)
        #expect(settings.followsAuthorizationHeader == false)
        #expect(settings.maxRedirects == 20)
        #expect(settings.timeoutSeconds == nil)
    }

    @Test func `the empty Draft is GET with nothing else`() {
        let emptyDraft = RequestDefinition(
            method: "GET", url: "", params: [], headers: [], cookies: [],
            body: .none, auth: .none,
            settings: RequestSettings(allowsInsecureTLS: false, followsRedirects: false)
        )
        #expect(RequestDefinition.empty == emptyDraft)
    }
}

import RaccoonDomain
import Testing

/// curl.md: `CurlImporter.import(CurlRenderer.render(r))` gives back `r`, one test for both
/// directions, over every Yaak and Bruno fixture with a request and no Variables.
struct CurlRoundTripTests {
    static let fixtures = YaakCurlFixtures.all + BrunoCurlFixtures.all

    /// Each expects an error, so there is no request to render.
    static let excluded: Set<String> = [
        "Missing URL",
        "Throws on malformed quotes",
        "should handle complex escaped quotes",
        "should parse a complex curl command with multiple features and no protocol",
        "should parse a complex curl command with multiple features",
        "should parse a curl command with complex escape characters",
        "should handle JSON with escaped quotes",
    ]

    static let roundTrippable = fixtures.compactMap { fixture -> RequestDefinition? in
        guard case .success(let imported) = fixture.expected, !fixture.input.contains("{{") else { return nil }
        return imported.definition
    }

    @Test func `only the fixtures that expect an error are left out`() {
        let failing = Self.fixtures.filter { if case .failure = $0.expected { true } else { false } }
        #expect(Set(failing.map(\.name)) == Self.excluded)
        #expect(Self.roundTrippable.count == Self.fixtures.count - Self.excluded.count)
    }

    @Test(arguments: roundTrippable)
    func `importing the rendered command gives the definition back`(definition: RequestDefinition) throws {
        let text = CurlRenderer.render(try VariableResolver.resolve(definition))
        #expect(try CurlImporter.import(text).definition == definition, "\(text)")
    }
}

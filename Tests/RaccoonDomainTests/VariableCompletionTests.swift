import Foundation
import RaccoonDomain
import Testing

struct VariableCompletionTests {
    /// (text, caret, expected prefix or nil)
    static let queries: [(String, Int, String?)] = [
        ("{{", 2, ""),
        ("https://{{ho", 12, "ho"),
        ("Bearer {{bearer", 15, "bearer"),
        ("{{api.v2_key-1", 14, "api.v2_key-1"),
        ("{{host}}", 8, nil),
        ("{{ho st", 7, nil),
        ("{ho", 3, nil),
        ("ho", 2, nil),
        ("{{ho", 3, "h"),
        ("", 0, nil),
        ("東京{{x", 5, "x"),
    ]

    @Test(arguments: queries)
    func `the query is the name typed after {{ up to the caret`(text: String, caret: Int, prefix: String?) {
        let query = VariableCompletion.query(in: text, caret: caret)
        #expect(query?.prefix == prefix)
        if let query { #expect(NSMaxRange(query.range) == caret && query.range.length == (prefix ?? "").utf16.count) }
    }

    static let insertions: [(String, Int, String, String, Int)] = [
        ("https://{{ho", 12, "host", "https://{{host}}", 16),
        ("{{ho}}/x", 4, "host", "{{host}}/x", 8),
        ("{{hoxx}}", 4, "host", "{{host}}", 8),
        ("{{ho}/x", 4, "host", "{{host}}}/x", 8),
        ("a {{ b", 4, "bearerToken", "a {{bearerToken}} b", 17),
    ]

    @Test(arguments: insertions)
    func `accepting writes name}} over the typed name, the rest of it and a }} already there`(text: String, caret: Int, name: String, after: String, newCaret: Int) throws {
        let query = try #require(VariableCompletion.query(in: text, caret: caret))
        let insertion = VariableCompletion.insertion(of: VariableName(name)!, for: query, in: text)

        let result = (text as NSString).replacingCharacters(in: insertion.range, with: insertion.text)
        #expect(result == after)
        #expect(insertion.caret == newCaret)
    }

    func entry(_ name: String, _ value: VariableEntry.Value, enabled: Bool = true) -> VariableEntry {
        VariableEntry(name: VariableName(name)!, isEnabled: enabled, value: value)
    }

    var kinds: VariableKinds {
        VariableKinds(
            active: Environment(name: "Staging", entries: [entry("host", .plain("s")), entry("tenantToken", .secret), entry("skip", .plain("x"), enabled: false)]),
            globals: Globals(entries: [entry("host", .plain("g")), entry("bearerToken", .secret), entry("path", .plain("/"))])
        )
    }

    @Test func `every enabled name in scope is offered by name, with its winning source, never a value`() {
        #expect(kinds.suggestions(matching: "") == [
            VariableSuggestion(name: VariableName("bearerToken")!, source: "Globals", isSecret: true),
            VariableSuggestion(name: VariableName("host")!, source: "Staging", isSecret: false),
            VariableSuggestion(name: VariableName("path")!, source: "Globals", isSecret: false),
            VariableSuggestion(name: VariableName("tenantToken")!, source: "Staging", isSecret: true),
        ])
    }

    @Test func `matching ignores case, and names that start with it come first`() {
        #expect(kinds.suggestions(matching: "TOKEN").map(\.name.rawValue) == ["bearerToken", "tenantToken"])
        #expect(kinds.suggestions(matching: "t").map(\.name.rawValue) == ["tenantToken", "bearerToken", "host", "path"])
        #expect(kinds.suggestions(matching: "nope").isEmpty)
        #expect(kinds.suggestions(matching: "skip").isEmpty)
    }
}

import AppKit
@testable import Raccoon
import RaccoonDomain
import Testing

/// Which tokens colour a body editor's text: the raw kind's, or the GraphQL ones (design-system.md §6).
@MainActor
struct BodySyntaxTests {
    @Test(arguments: [
        (BodySyntax.graphql, "query { a }", ColorToken.jsonBoolean, NSRange(location: 0, length: 5)),
        (.raw(.json), #"{"a": 1}"#, .jsonKey, NSRange(location: 1, length: 3)),
        (.raw(.json), #"{"a": 1}"#, .jsonNumber, NSRange(location: 6, length: 1)),
    ] as [(BodySyntax, String, ColorToken, NSRange)])
    func `a syntax colours its own tokens`(syntax: BodySyntax, text: String, token: ColorToken, range: NSRange) {
        #expect(syntax.ranges(text).contains(HighlightRange(range: range, token: token)))
    }

    @Test func `text is not coloured`() {
        #expect(BodySyntax.raw(.text).ranges(#"{"a": 1}"#).isEmpty)
    }

    @Test func `the Variables are JSON, so a GraphQL keyword is not coloured as one`() {
        #expect(!BodySyntax.raw(.json).ranges("query").contains { $0.token == .jsonBoolean })
    }
}

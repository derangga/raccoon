import Foundation
import RaccoonDomain
import Testing

struct HighlighterTests {
    static func r(_ location: Int, _ length: Int, _ token: ColorToken) -> HighlightRange {
        HighlightRange(range: NSRange(location: location, length: length), token: token)
    }

    @Test(arguments: [
        (#"{"a": 1.5, "b": [true, null, "x"]}"#, [
            r(0, 1, .jsonPunctuation), r(1, 3, .jsonKey), r(4, 1, .jsonPunctuation), r(6, 3, .jsonNumber),
            r(9, 1, .jsonPunctuation), r(11, 3, .jsonKey), r(14, 1, .jsonPunctuation), r(16, 1, .jsonPunctuation),
            r(17, 4, .jsonBoolean), r(21, 1, .jsonPunctuation), r(23, 4, .jsonNull), r(27, 1, .jsonPunctuation),
            r(29, 3, .jsonString), r(32, 1, .jsonPunctuation), r(33, 1, .jsonPunctuation),
        ]),
        ("{\"k\\\"é\" : \"😀\"}", [
            r(0, 1, .jsonPunctuation), r(1, 6, .jsonKey), r(8, 1, .jsonPunctuation), r(10, 4, .jsonString), r(14, 1, .jsonPunctuation),
        ]),
        (#"{"a": {{amount}}}"#, [r(0, 1, .jsonPunctuation), r(1, 3, .jsonKey), r(4, 1, .jsonPunctuation), r(16, 1, .jsonPunctuation)]),
        (#"{"half": "unterminated"#, [r(0, 1, .jsonPunctuation), r(1, 6, .jsonKey), r(7, 1, .jsonPunctuation), r(9, 13, .jsonString)]),
        ("-2e10 false", [r(0, 5, .jsonNumber), r(6, 5, .jsonBoolean)]),
    ])
    func `JSON ranges carry their syntax token`(text: String, ranges: [HighlightRange]) {
        #expect(Highlighter.ranges(text, kind: .json) == ranges)
    }

    @Test(arguments: [
        (#"<a id="1" x='y'>t</a>"#, [
            r(0, 2, .xmlTag), r(3, 2, .xmlAttribute), r(5, 1, .jsonPunctuation), r(6, 3, .xmlValue),
            r(10, 1, .xmlAttribute), r(11, 1, .jsonPunctuation), r(12, 3, .xmlValue), r(15, 1, .xmlTag),
            r(17, 3, .xmlTag), r(20, 1, .xmlTag),
        ]),
        ("<!-- <x> --><b/>", [r(12, 2, .xmlTag), r(14, 2, .xmlTag)]),
        (#"<?xml version="1.0"?>"#, [r(0, 5, .xmlTag), r(6, 7, .xmlAttribute), r(13, 1, .jsonPunctuation), r(14, 5, .xmlValue), r(19, 2, .xmlTag)]),
    ])
    func `XML ranges carry their syntax token`(text: String, ranges: [HighlightRange]) {
        #expect(Highlighter.ranges(text, kind: .xml) == ranges)
    }

    static let (flag, punct, key, string) = (ColorToken.curlFlag, ColorToken.jsonPunctuation, ColorToken.jsonKey, ColorToken.jsonString)

    @Test(arguments: [
        // A GET: the command word, then the URL between its quotes.
        ("curl 'https://api.test/items'", [r(0, 4, flag), r(5, 1, punct), r(6, 22, .text), r(28, 1, punct)]),
        // A POST with a header and a JSON body, over three lines.
        ("curl -X POST 'https://a.io/v1' \\\n  -H 'Content-Type: application/json' \\\n  --data-raw '{\"a\": 1}'", [
            r(0, 4, flag), r(5, 2, flag), r(8, 4, .methodPost), r(13, 1, punct), r(14, 15, .text), r(29, 1, punct),
            r(31, 1, punct), r(35, 2, flag), r(38, 1, punct), r(39, 12, key), r(51, 1, punct), r(53, 16, string),
            r(69, 1, punct), r(71, 1, punct), r(75, 10, flag), r(86, 1, punct), r(87, 8, string), r(95, 1, punct),
        ]),
        // A quote inside a header value, written '\'' by CurlRenderer, stays in the value.
        ("curl 'https://a.io' \\\n  -H 'X-Note: it'\\''s fine'", [
            r(0, 4, flag), r(5, 1, punct), r(6, 12, .text), r(18, 1, punct), r(20, 1, punct), r(24, 2, flag),
            r(27, 1, punct), r(28, 6, key), r(34, 1, punct), r(36, 12, string), r(48, 1, punct),
        ]),
        // {{token}} is left out, for the Variable highlight drawn on top.
        ("curl 'https://a.io' \\\n  -H 'Authorization: Bearer {{token}}'", [
            r(0, 4, flag), r(5, 1, punct), r(6, 12, .text), r(18, 1, punct), r(20, 1, punct), r(24, 2, flag),
            r(27, 1, punct), r(28, 13, key), r(41, 1, punct), r(43, 7, string), r(59, 1, punct),
        ]),
        // An unterminated quote runs to the end.
        ("curl -X POST 'https://a.io", [r(0, 4, flag), r(5, 2, flag), r(8, 4, .methodPost), r(13, 1, punct), r(14, 12, .text)]),
        // A switch takes no value, so the next word is the URL; an empty header ends in `;`.
        ("curl -k 'https://a.io' -H 'X-E;'", [
            r(0, 4, flag), r(5, 2, flag), r(8, 1, punct), r(9, 12, .text), r(21, 1, punct), r(23, 2, flag),
            r(26, 1, punct), r(27, 3, key), r(30, 1, punct), r(31, 1, punct),
        ]),
    ])
    func `curl command ranges carry their token`(command: String, ranges: [HighlightRange]) {
        #expect(Highlighter.curl(command) == ranges)
    }

    static let (kw, name, null, num, tert) = (ColorToken.jsonBoolean, ColorToken.jsonKey, ColorToken.jsonNull, ColorToken.jsonNumber, ColorToken.textTertiary)

    // The rule: a keyword (`query`, `mutation`, `subscription`, `fragment`, `on`, `true`, `false`) is
    // jsonBoolean and `null` is jsonNull; every other name, a field, an argument or a type, is jsonKey.
    @Test(arguments: [
        // Keywords and names, each with its own colour.
        ("query Q { a }", [r(0, 5, kw), r(6, 1, name), r(8, 1, punct), r(10, 1, name), r(12, 1, punct)]),
        // A GraphQL variable (`$id`) is jsonNull, `$` included; an argument name is jsonKey; a number is jsonNumber.
        ("user(id: $id, n: -2e3)", [
            r(0, 4, name), r(4, 1, punct), r(5, 2, name), r(7, 1, punct), r(9, 3, null), r(12, 1, punct),
            r(14, 1, name), r(15, 1, punct), r(17, 4, num), r(21, 1, punct),
        ]),
        // A string with an escaped quote and a block string holding quotes.
        (#"a(s: "x\"y", t: """b "c" """)"#, [
            r(0, 1, name), r(1, 1, punct), r(2, 1, name), r(3, 1, punct), r(5, 6, string), r(11, 1, punct),
            r(13, 1, name), r(14, 1, punct), r(16, 12, string), r(28, 1, punct),
        ]),
        // A comment runs to the end of its line; `fragment` and `on` are keywords; `@` is punctuation.
        ("# hi\nfragment F on T @a", [
            r(0, 4, tert), r(5, 8, kw), r(14, 1, name), r(16, 2, kw), r(19, 1, name), r(21, 1, punct), r(22, 1, name),
        ]),
        // `...` is one punctuation range; the type wrappers and operators are punctuation.
        ("...on T", [r(0, 3, punct), r(3, 2, kw), r(6, 1, name)]),
        ("[A!]=|&", [r(0, 1, punct), r(1, 1, name), r(2, 1, punct), r(3, 1, punct), r(4, 1, punct), r(5, 1, punct), r(6, 1, punct)]),
        // `true` and `false` are keywords, `null` is jsonNull, `1.5e3` is one number.
        ("true false null 1.5e3", [r(0, 4, kw), r(5, 5, kw), r(11, 4, null), r(16, 5, num)]),
    ])
    func `GraphQL ranges carry their token`(text: String, ranges: [HighlightRange]) {
        #expect(Highlighter.graphql(text) == ranges)
    }

    @Test(arguments: [
        // A block string closes at the first `"""` that is not escaped as `\"""`.
        ("\"\"\"a\\\"\"\" b\"\"\" x", [r(0, 13, string), r(14, 1, name)]),
        // Ranges are UTF-16 offsets: an emoji is two units, é one.
        ("\"😀é\" a", [r(0, 5, string), r(6, 1, name)]),
        ("# 😀\nb", [r(0, 4, tert), r(5, 1, name)]),
        // An unterminated string ends at its line, and the later lines still colour.
        ("a(s: \"half\nb { c }", [
            r(0, 1, name), r(1, 1, punct), r(2, 1, name), r(3, 1, punct), r(5, 5, string),
            r(11, 1, name), r(13, 1, punct), r(15, 1, name), r(17, 1, punct),
        ]),
        ("\"x\r\nb", [r(0, 2, string), r(4, 1, name)]),
        ("\"a\\\nb", [r(0, 3, string), r(4, 1, name)]),
        // An unterminated string and an unterminated block string are coloured to the end.
        (#"a(s: "half"#, [r(0, 1, name), r(1, 1, punct), r(2, 1, name), r(3, 1, punct), r(5, 5, string)]),
        (#""""abc"#, [r(0, 6, string)]),
        // Text that does not lex is plain from there on.
        ("a ~ b", [r(0, 1, name)]),
        ("a $ b", [r(0, 1, name)]),
        ("", []),
    ])
    func `GraphQL ranges stop, end and measure as the text says`(text: String, ranges: [HighlightRange]) {
        #expect(Highlighter.graphql(text) == ranges)
    }

    // A Variable ({{id}}) is left out, bare or inside a string, for the Variable highlight drawn on top.
    @Test(arguments: [
        (#"a(id: {{id}}) { b }"#, [
            r(0, 1, name), r(1, 1, punct), r(2, 2, name), r(4, 1, punct), r(12, 1, punct), r(14, 1, punct), r(16, 1, name), r(18, 1, punct),
        ]),
        (#""a{{x}}b""#, [r(0, 2, string), r(7, 2, string)]),
        ("# a {{x}}", [r(0, 4, tert)]),
        ("\"\"\"a {{x}} b\"\"\"", [r(0, 5, string), r(10, 5, string)]),
        (#""{{a}}-{{b}}""#, [r(0, 1, string), r(6, 1, string), r(12, 1, string)]),
    ])
    func `GraphQL ranges leave a Variable uncovered`(text: String, ranges: [HighlightRange]) {
        let actual = Highlighter.graphql(text)
        #expect(actual == ranges)
        for token in VariableTokens.ranges(text) {
            #expect(!actual.contains { NSIntersectionRange($0.range, token.range).length > 0 })
        }
    }

    @Test func `a Variable in a query is still marked on top`() {
        let text = #"{ a(id: "{{id}}") }"#
        #expect(VariableTokens.ranges(text).map(\.range) == [NSRange(location: 9, length: 6)])
        #expect(Highlighter.graphql(text).contains { $0.token == .jsonString })
    }

    @Test func `text has no ranges`() {
        #expect(Highlighter.ranges(#"{"a": 1}"#, kind: .text).isEmpty)
    }
}

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

    @Test func `text has no ranges`() {
        #expect(Highlighter.ranges(#"{"a": 1}"#, kind: .text).isEmpty)
    }
}

import Foundation
import RaccoonDomain
import Testing

struct DocsStyleTests {
    static func r(_ location: Int, _ length: Int, _ style: DocsStyle.Style) -> DocsStyleRange {
        DocsStyleRange(range: NSRange(location: location, length: length), style: style)
    }

    @Test(arguments: [
        // headings 1 to 3 (and 4, which the pane draws like 3): the hashes are marks, the text is the heading
        ("# Title", [r(0, 1, .mark), r(2, 5, .heading(level: 1))]),
        ("## Auth", [r(0, 2, .mark), r(3, 4, .heading(level: 2))]),
        ("### Steps", [r(0, 3, .mark), r(4, 5, .heading(level: 3))]),
        ("#### Deep", [r(0, 4, .mark), r(5, 4, .heading(level: 4))]),
        // bold, italic, inline code: marks around the text
        ("a **b** c", [r(2, 2, .mark), r(4, 1, .bold), r(5, 2, .mark)]),
        ("a *b* c", [r(2, 1, .mark), r(3, 1, .italic), r(4, 1, .mark)]),
        ("run `curl -v` now", [r(4, 1, .mark), r(5, 7, .code), r(12, 1, .mark)]),
        // a fenced block: the fences are marks, the lines between are the block
        ("```json\n{\"a\": 1}\n```", [r(0, 7, .mark), r(8, 8, .codeBlock), r(17, 3, .mark)]),
        // a fence never closed runs to the end
        ("```\nx\ny", [r(0, 3, .mark), r(4, 3, .codeBlock)]),
        // lists and quotes: the marker, then the text styled inline
        ("- one\n1. two", [r(0, 1, .listMarker), r(6, 2, .listMarker)]),
        ("* a *b*", [r(0, 1, .listMarker), r(4, 1, .mark), r(5, 1, .italic), r(6, 1, .mark)]),
        ("> note", [r(0, 1, .quoteMark), r(2, 4, .quote)]),
        // a link: only http and https carry a URL to open
        ("[docs](https://a.io/x)", [r(0, 1, .mark), r(1, 4, .link(url: "https://a.io/x")), r(5, 17, .mark)]),
        ("[mail](mailto:a@b.io)", [r(0, 1, .mark), r(1, 4, .link(url: nil)), r(5, 16, .mark)]),
        // CRLF: the CR belongs to no range
        ("# T\r\n- a", [r(0, 1, .mark), r(2, 1, .heading(level: 1)), r(5, 1, .listMarker)]),
    ])
    func `markdown is styled in place and every mark is kept`(text: String, ranges: [DocsStyleRange]) {
        #expect(DocsStyle.ranges(text) == ranges)
    }

    @Test func `a heading's inline marks are styled over it`() {
        #expect(DocsStyle.ranges("## a **b** c") == [
            Self.r(0, 2, .mark), Self.r(3, 9, .heading(level: 2)),
            Self.r(5, 2, .mark), Self.r(7, 1, .bold), Self.r(8, 2, .mark),
        ])
        #expect(DocsStyle.ranges("# `x` ~~y~~") == [
            Self.r(0, 1, .mark), Self.r(2, 9, .heading(level: 1)),
            Self.r(2, 1, .mark), Self.r(3, 1, .code), Self.r(4, 1, .mark),
            Self.r(6, 2, .mark), Self.r(8, 1, .strikethrough), Self.r(9, 2, .mark),
        ])
    }

    @Test func `strikethrough is styled between its marks`() {
        #expect(DocsStyle.ranges("a ~~b~~ c") == [Self.r(2, 2, .mark), Self.r(4, 1, .strikethrough), Self.r(5, 2, .mark)])
    }

    @Test(arguments: [
        "a ** b", "~~open", "~one~", "a ~~ b ~~", "**open", "*open", "`open", "[text]", "[text](", "[text]()", "[](x)", "2 * 3 * 4",
        "#nospace", "####### seven", "snake_case_name", "{{name}}", "-nospace", "1.nospace", ">", "", "\n\n",
    ])
    func `unmatched marks are drawn as text`(text: String) {
        #expect(DocsStyle.ranges(text).filter { $0.style != .quoteMark } == [])
    }

    @Test func `braces in Docs are plain text`() {
        #expect(DocsStyle.ranges("Send {{token}} as the bearer").isEmpty)
    }

    @Test(arguments: ["**é** 😀 `x` [a](http://b)", "```\n\u{0}\r\n*", "> *a\n- **b\n# `c", "[a]\n(b)", "\u{2028}*x*"])
    func `every range lies inside the text`(text: String) {
        let length = text.utf16.count
        for range in DocsStyle.ranges(text) {
            #expect(range.range.location >= 0 && NSMaxRange(range.range) <= length)
        }
    }
}

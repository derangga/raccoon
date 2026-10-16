import RaccoonDomain
import Testing

struct BodyFormatterTests {
    @Test(arguments: [
        (#"{"amount": {{amount}}, "currency":"usd"}"#,
         "{\n  \"amount\": {{amount}},\n  \"currency\": \"usd\"\n}"),
        (#"{"z":1.50,"a":[1,-2e10,{"b":null}],"e":{},"f":[ ],"t":true}"#,
         "{\n  \"z\": 1.50,\n  \"a\": [\n    1,\n    -2e10,\n    {\n      \"b\": null\n    }\n  ],\n  \"e\": {},\n  \"f\": [],\n  \"t\": true\n}"),
        (#"  {"s" : "a \"{{x}}\" , bé\n"}  "#,
         "{\n  \"s\": \"a \\\"{{x}}\\\" , bé\\n\"\n}"),
        (#"[{{items}}, "x"]"#, "[\n  {{items}},\n  \"x\"\n]"),
        ("42", "42"),
        ("{\"u\":\"\\" + "u00e9\"}", "{\n  \"u\": \"\\" + "u00e9\"\n}"),
    ])
    func `JSON is re-indented by 2 and nothing but whitespace changes`(text: String, formatted: String) throws {
        #expect(try BodyFormatter.format(text, kind: .json) == formatted)
        #expect(try BodyFormatter.format(formatted, kind: .json) == formatted)
    }

    @Test(arguments: [
        ("{\n  \"amount\": 2000,\n  \"currency\" \"usd\",\n}", 3, 14),
        (#"{"a": 01}"#, 1, 8),
        (#"{"a": 1,}"#, 1, 9),
        (#"{"a": "unterminated}"#, 1, 21),
        (#"[1] 2"#, 1, 5),
        ("", 1, 1),
    ])
    func `a body that is not JSON reports where it stopped`(text: String, line: Int, column: Int) {
        #expect(throws: FormatError.notValid(line: line, column: column)) {
            try BodyFormatter.format(text, kind: .json)
        }
    }

    @Test(arguments: [
        (#"<?xml version="1.0"?><order id="1" currency="usd"><item sku="a" qty="2"/><note>Hi {{name}}</note><!-- c --></order>"#,
         "<?xml version=\"1.0\"?>\n<order id=\"1\" currency=\"usd\">\n  <item sku=\"a\" qty=\"2\"/>\n  <note>Hi {{name}}</note>\n  <!-- c -->\n</order>"),
        ("<a>\n    <b   z=\"1\"  a=\"2\">x</b>\n\n</a>", "<a>\n  <b   z=\"1\"  a=\"2\">x</b>\n</a>"),
        ("<a><b></b>text<c/></a>", "<a>\n  <b></b>\n  text\n  <c/>\n</a>"),
    ])
    func `XML is re-indented by 2 and every tag is kept as written`(text: String, formatted: String) throws {
        #expect(try BodyFormatter.format(text, kind: .xml) == formatted)
        #expect(try BodyFormatter.format(formatted, kind: .xml) == formatted)
    }

    @Test(arguments: [
        ("<a>\n  <b></c>\n</a>", 2, 6),
        ("<a><b>", 1, 7),
        ("</a>", 1, 1),
        ("<a attr=\"x>", 1, 12),
    ])
    func `XML that does not nest reports where it stopped`(text: String, line: Int, column: Int) {
        #expect(throws: FormatError.notValid(line: line, column: column)) {
            try BodyFormatter.format(text, kind: .xml)
        }
    }

    @Test func `text is returned as it is`() throws {
        #expect(try BodyFormatter.format("  {not json", kind: .text) == "  {not json")
    }
}

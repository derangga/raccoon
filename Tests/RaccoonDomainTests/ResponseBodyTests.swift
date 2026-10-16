import Foundation
import RaccoonDomain
import Testing

struct ResponseBodyTests {
    func response(_ body: Data, contentType: String? = nil) -> Response {
        Response(
            status: 200,
            headers: contentType.map { [Response.Header(name: "Content-Type", value: $0)] } ?? [],
            body: body, elapsed: .milliseconds(88), byteCount: body.count
        )
    }

    @Test(arguments: [
        (#"{"a":1}"#, "text/plain", .pretty("{\n  \"a\": 1\n}", .json)),
        (#"{"a":1}"#, "application/xml", .pretty("{\n  \"a\": 1\n}", .json)),
        ("<a><b>x</b></a>", "application/json", .pretty("<a>\n  <b>x</b>\n</a>", .xml)),
        ("<a><b>x</b></a>", nil, .pretty("<a>\n  <b>x</b>\n</a>", .xml)),
        ("<!doctype html><p>Hi<br></body>", "application/json", .raw("<!doctype html><p>Hi<br></body>")),
        ("hello", "text/plain", .raw("hello")),
        (#"{"a": 1,}"#, "application/json", .raw(#"{"a": 1,}"#)),
        ("", nil, .raw("")),
    ] as [(String, String?, ResponseBody)])
    func `Pretty is decided by parsing, Content-Type only picks the parser to try first`(
        body: String, contentType: String?, expected: ResponseBody
    ) {
        #expect(ResponseBody.presentation(response(Data(body.utf8), contentType: contentType)) == expected)
    }

    @Test func `a body that is not UTF-8 is binary, not an error`() {
        #expect(ResponseBody.presentation(response(Data([0xFF, 0xFE, 0x00, 0x81]))) == .binary(byteCount: 4))
    }

    @Test func `a body above the threshold is raw even when it parses`() {
        let atLimit = "[" + String(repeating: " ", count: ResponseBody.prettyThreshold - 2) + "]"
        let over = atLimit + " "
        #expect(ResponseBody.presentation(response(Data(atLimit.utf8))) == .pretty("[]", .json))
        #expect(ResponseBody.presentation(response(Data(over.utf8))) == .raw(over))
    }
}

struct StatusLineTests {
    @Test(arguments: [
        (200, "OK", ColorToken.status2xx),
        (101, "Switching Protocols", .status1xx),
        (301, "Moved Permanently", .status3xx),
        (404, "Not Found", .status4xx),
        (511, "Network Authentication Required", .status5xx),
        (299, "", .status2xx),
    ])
    func `the code carries its reason and its status color`(status: Int, reason: String, token: ColorToken) {
        let line = StatusLine(status: status, elapsed: .milliseconds(88), byteCount: 0)
        #expect(line.code == "\(status)")
        #expect(line.reason == reason)
        #expect(line.token == token)
    }

    @Test(arguments: [
        (Duration.milliseconds(3), "3 ms"),
        (.microseconds(88_400), "88 ms"),
        (.milliseconds(999), "999 ms"),
        (.milliseconds(1_000), "1.0 s"),
        (.milliseconds(1_440), "1.4 s"),
        (.seconds(60), "60.0 s"),
    ])
    func `elapsed is in ms under a second, then seconds to one decimal`(elapsed: Duration, text: String) {
        #expect(StatusLine(status: 200, elapsed: elapsed, byteCount: 0).elapsed == text)
    }

    @Test(arguments: [
        (0, "0 B"),
        (999, "999 B"),
        (48_200, "48.2 KB"),
        (20_400_000, "20.4 MB"),
        (1_500_000_000, "1.5 GB"),
    ])
    func `size uses decimal units with one decimal`(byteCount: Int, text: String) {
        #expect(StatusLine(status: 200, elapsed: .zero, byteCount: byteCount).size == text)
    }
}

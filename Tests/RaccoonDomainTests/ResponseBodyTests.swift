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

    @Test(arguments: [
        ("image/webp", "image/webp"),
        ("image/avif", "image/avif"),
        ("IMAGE/PNG; charset=binary", "image/png"),
        (" image/jpeg ", "image/jpeg"),
    ])
    func `an image Content-Type is an image, whatever the bytes are`(contentType: String, mediaType: String) {
        let bytes = Data([0xFF, 0xD8, 0xFF, 0xE0])
        #expect(ResponseBody.presentation(response(bytes, contentType: contentType)) == .image(mediaType: mediaType))
        // UTF-8 bytes under an image type are still the image's to decode, not text.
        #expect(ResponseBody.presentation(response(Data("GIF89a".utf8), contentType: contentType)) == .image(mediaType: mediaType))
    }

    @Test(arguments: [
        ("image/avif", "image/avif"),
        ("IMAGE/PNG; charset=binary", "image/png"),
        (" image/jpeg ", "image/jpeg"),
    ])
    func `the image media type is read from the header alone, without the presentation`(contentType: String, mediaType: String) {
        #expect(ResponseBody.imageMediaType(response(Data("not a picture".utf8), contentType: contentType)) == mediaType)
    }

    @Test(arguments: ["image/svg+xml", "text/plain", "application/octet-stream", "x-image/webp", "image"] as [String?] + [nil])
    func `no image media type for other or missing Content-Types`(contentType: String?) {
        #expect(ResponseBody.imageMediaType(response(Data([0xFF, 0xD8]), contentType: contentType)) == nil)
    }

    @Test(arguments: ["image/svg+xml", "text/plain", "application/json", "application/octet-stream", "x-image/webp"])
    func `other Content-Types are not images`(contentType: String) {
        #expect(ResponseBody.presentation(response(Data([0xFF, 0xD8]), contentType: contentType)) == .binary(byteCount: 2))
    }

    @Test func `a body above the threshold is raw even when it parses`() {
        let atLimit = "[" + String(repeating: " ", count: ResponseBody.prettyThreshold - 2) + "]"
        let over = atLimit + " "
        #expect(ResponseBody.presentation(response(Data(atLimit.utf8))) == .pretty("[]", .json))
        #expect(ResponseBody.presentation(response(Data(over.utf8))) == .raw(over))
    }

    @Test func `the disabled-Pretty note names the measured threshold`() {
        #expect(ResponseBody.prettyThreshold == 5_000_000)
        #expect(ResponseBody.prettyOffNote == "Pretty is off above 5 MB")
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

struct FailureTextTests {
    @Test(arguments: [
        (SendError.timedOut, "No response after 60 s", "The server did not answer in time. Raccoon does not send again by itself.", false),
        (.untrustedCertificate(host: "grafana.staging.internal.example.com"), "Untrusted certificate",
         "The certificate for grafana.staging.internal.example.com is not trusted by this Mac. It may be self-signed or expired.", true),
        (.transport(.cannotConnectToHost, "Could not connect to the server.", host: "localhost:8080"), "Could not connect to the server",
         "NSURLErrorCannotConnectToHost (−1004) · localhost:8080", false),
        (.transport(.dnsLookupFailed, "A server with the specified hostname could not be found.", host: "nope.invalid"),
         "A server with the specified hostname could not be found", "NSURLErrorDNSLookupFailed (−1006) · nope.invalid", false),
        (.transport(URLError.Code(rawValue: -4242), "Something odd.", host: "h"), "Something odd", "URLError (−4242) · h", false),
        (.fileMissing(path: "~/Desktop/box.jpg"), "File missing", "~/Desktop/box.jpg is missing, so nothing was sent.", false),
    ])
    func `each send failure has a title, one sentence, and the fix only when there is one`(
        error: SendError, title: String, detail: String, offersInsecureTLS: Bool
    ) {
        let text = FailureText(error)
        #expect(text.title == title)
        #expect(text.detail == detail)
        #expect(text.offersInsecureTLS == offersInsecureTLS)
    }
}

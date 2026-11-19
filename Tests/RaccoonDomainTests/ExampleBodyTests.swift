import Foundation
import RaccoonDomain
import Testing

struct ExampleBodyTests {
    @Test(arguments: [
        (Data(), ExampleBody.text("")),
        (Data("hello".utf8), .text("hello")),
        (Data("café ☕".utf8), .text("café ☕")),
        (Data([0xFF, 0xFE, 0x00]), .bytes(Data([0xFF, 0xFE, 0x00]))),
        (Data([0xC3, 0x28]), .bytes(Data([0xC3, 0x28]))),
        (Data([0x89, 0x50, 0x4E, 0x47]), .bytes(Data([0x89, 0x50, 0x4E, 0x47]))),
    ])
    func `bytes are text when they are UTF-8, and bytes otherwise`(data: Data, expected: ExampleBody) {
        #expect(ExampleBody(bytes: data) == expected)
    }

    static func example(_ headers: [Row]) -> Example {
        Example(id: ExampleID(UUID()), name: "ok", status: 200, headers: headers, body: .text(""))
    }

    @Test(arguments: [
        ([Row(name: "Content-Type", value: "application/json")], "application/json"),
        ([Row(name: "content-type", value: "text/plain; charset=utf-8")], "text/plain; charset=utf-8"),
        ([Row(name: "CONTENT-TYPE", value: "a"), Row(name: "Content-Type", value: "b")], "a"),
        ([Row(name: "Content-Type", value: "x", isEnabled: false), Row(name: "Content-Type", value: "y")], "y"),
    ])
    func `the Content-Type is the first enabled row of that name, any case`(headers: [Row], expected: String) {
        #expect(Self.example(headers).contentType == expected)
    }

    @Test(arguments: [
        [Row](),
        [Row(name: "X-Other", value: "application/json")],
        [Row(name: "Content-Type", value: "application/json", isEnabled: false)],
    ])
    func `no enabled Content-Type row is no Content-Type`(headers: [Row]) {
        #expect(Self.example(headers).contentType == nil)
    }

    @Test(arguments: [
        ("application/json", RawKind.json),
        ("application/json; charset=utf-8", .json),
        ("Application/JSON", .json),
        ("application/problem+json", .json),
        ("application/vnd.api+json;charset=utf-8", .json),
        ("application/xml", .xml),
        ("text/xml; charset=utf-8", .xml),
        ("application/soap+xml", .xml),
        ("text/plain", .text),
        ("text/html", .text),
        ("application/jsonp", .text),
        ("application/octet-stream", .text),
        ("", .text),
    ])
    func `a Content-Type colours the body as JSON, XML or plain`(contentType: String, expected: RawKind) {
        let example = Self.example([Row(name: "Content-Type", value: contentType)])
        #expect(example.bodySyntax == expected)
    }

    @Test func `an Example without a Content-Type is plain`() {
        #expect(Self.example([]).bodySyntax == .text)
    }
}

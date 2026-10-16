import RaccoonDomain
import Testing

struct BodyConversionTests {
    static let raw = Body.raw(.json, "{\"a\": 1}")
    static let form = Body.formURLEncoded([Row(name: "a", value: "1"), Row(name: "b", value: "2", isEnabled: false)])
    static let multipart = Body.multipart([
        Part(name: "a", content: .text("1")),
        Part(name: "f", content: .file(path: "/tmp/f.png")),
        Part(name: "b", isEnabled: false, content: .text("2")),
    ])

    @Test(arguments: [
        (raw, BodyType.raw(.xml), Body.raw(.xml, "{\"a\": 1}")),
        (raw, .raw(.json), raw),
        (raw, .formURLEncoded, .formURLEncoded([])),
        (raw, .multipart, .multipart([])),
        (raw, .none, .none),
        (form, .multipart, .multipart([Part(name: "a", content: .text("1")), Part(name: "b", isEnabled: false, content: .text("2"))])),
        (form, .formURLEncoded, form),
        (form, .raw(.text), .raw(.text, "")),
        (form, .none, .none),
        (multipart, .formURLEncoded, form),
        (multipart, .multipart, multipart),
        (multipart, .raw(.json), .raw(.json, "")),
        (multipart, .none, .none),
        (Body.none, .raw(.json), .raw(.json, "")),
        (Body.none, .formURLEncoded, .formURLEncoded([])),
        (Body.none, .multipart, .multipart([])),
        (Body.none, .none, .none),
    ])
    func `each Body Type switch keeps what the new type can hold`(body: Body, type: BodyType, converted: Body) {
        #expect(BodyConversion.convert(body, to: type) == converted)
    }

    static let accept = Row(name: "Accept", value: "*/*")

    @Test(arguments: [
        ([accept], BodyType.none, BodyType.raw(.json), [accept, Row(name: "Content-Type", value: "application/json")]),
        ([Row(name: "content-type", value: "application/json"), accept], .raw(.json), .raw(.xml),
         [Row(name: "content-type", value: "application/xml"), accept]),
        ([Row(name: "Content-Type", value: "text/plain")], .raw(.text), .formURLEncoded,
         [Row(name: "Content-Type", value: "application/x-www-form-urlencoded")]),
        ([Row(name: "Content-Type", value: "application/x-www-form-urlencoded")], .formURLEncoded, .multipart,
         [Row(name: "Content-Type", value: "multipart/form-data")]),
        ([accept, Row(name: "Content-Type", value: "application/json")], .raw(.json), .none, [accept]),
        ([accept], .raw(.json), .none, [accept]),
    ])
    func `Content-Type follows the Body Type when the rule set it or none is set`(headers: [Row], from: BodyType, to: BodyType, result: [Row]) {
        #expect(Headers.contentType(headers, from: from, to: to) == result)
    }

    @Test(arguments: [
        [Row(name: "Content-Type", value: "application/vnd.api+json")],
        [Row(name: "Content-Type", value: "application/json", isEnabled: false)],
    ])
    func `a Content-Type the user set or disabled is never overwritten`(headers: [Row]) {
        #expect(Headers.contentType(headers, from: .raw(.json), to: .raw(.xml)) == headers)
        #expect(Headers.contentType(headers, from: .raw(.json), to: .none) == headers)
    }

    @Test func `a Body knows its Body Type`() {
        #expect([Body.none, Self.raw, Self.form, Self.multipart].map(\.type) == [.none, .raw(.json), .formURLEncoded, .multipart])
    }
}

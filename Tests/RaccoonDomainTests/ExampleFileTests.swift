import Foundation
import RaccoonDomain
import Testing

struct ExampleFileTests {
    static let first = ExampleID(UUID(uuidString: "E0000000-0000-4000-8000-000000000001")!)
    static let second = ExampleID(UUID(uuidString: "E0000000-0000-4000-8000-000000000002")!)

    static func request(_ examples: [Example]) throws -> Request {
        var request = try RequestFile.decode(Data(RequestFileTests.fixtures[0].utf8))
        request.examples = examples
        return request
    }

    static func file(examples: String) -> Data {
        Data(#"{"version": 1, "id": "6F1C2B3A-0000-4000-8000-000000000001", "name": "A", "method": "GET", "url": "x", "examples": \#(examples)}"#.utf8)
    }

    @Test(arguments: [
        Example(id: first, name: "ok", status: 200, headers: [Row(name: "Content-Type", value: "application/json")], body: .text(#"{"a":"café ☕"}"#)),
        Example(id: first, name: "image", status: 201, headers: [Row(name: "X", value: "1", isEnabled: false)], body: .bytes(Data([0, 255, 128, 7])), delayMilliseconds: 1500),
        Example(id: first, name: "empty", status: 204, body: .text("")),
    ])
    func `an Example round-trips through the Request file`(example: Example) throws {
        let request = try Self.request([example, Example(id: Self.second, name: "again", status: 500, body: .text("x"))])
        #expect(try RequestFile.decode(RequestFile.encode(request)) == request)
    }

    @Test func `the file holds text or base64, and leaves out a delay of 0`() throws {
        let text = String(decoding: RequestFile.encode(try Self.request([Example(id: Self.first, name: "t", status: 200, body: .text("hi"))])), as: UTF8.self)
        #expect(text.contains(#""text" : "hi""#) && !text.contains("base64") && !text.contains("delayMilliseconds"))
        let bytes = String(decoding: RequestFile.encode(try Self.request([Example(id: Self.first, name: "b", status: 200, body: .bytes(Data([1, 2, 3])), delayMilliseconds: 5)])), as: UTF8.self)
        #expect(bytes.contains(#""base64" : "AQID""#) && !bytes.contains(#""text""#) && bytes.contains(#""delayMilliseconds" : 5"#))
    }

    @Test func `a file without Examples gains no key`() throws {
        #expect(!String(decoding: RequestFile.encode(try Self.request([])), as: UTF8.self).contains("examples"))
        #expect(try RequestFile.decode(Data(RequestFileTests.fixtures[0].utf8)).examples == [])
    }

    @Test func `status and delay are clamped by the init`() {
        let example = Example(id: Self.first, name: "x", status: 99, body: .text(""), delayMilliseconds: 90000)
        #expect(example.status == 100 && example.delayMilliseconds == 60000)
        #expect(Example(id: Self.first, name: "x", status: 700, body: .text(""), delayMilliseconds: -1).status == 599)
    }

    @Test(arguments: [
        #"[{"id": "E0000000-0000-4000-8000-000000000001", "name": "a", "status": 200, "headers": [], "body": {}}]"#,
        #"[{"id": "E0000000-0000-4000-8000-000000000001", "name": "a", "status": 200, "headers": [], "body": {"text": "a", "base64": "YQ=="}}]"#,
        #"[{"id": "E0000000-0000-4000-8000-000000000001", "name": "a", "status": 200, "headers": [], "body": {"base64": "!!"}}]"#,
        #"[{"name": "a", "status": 200, "headers": [], "body": {"text": ""}}]"#,
        #"[{"id": "E0000000-0000-4000-8000-000000000001", "name": "a", "status": "ok", "headers": [], "body": {"text": ""}}]"#,
        #"{"not": "an array"}"#,
    ])
    func `a malformed entry makes the file malformed`(examples: String) {
        #expect(throws: RequestFileError.malformed("examples")) { try RequestFile.decode(Self.file(examples: examples)) }
    }

    @Test func `two Examples with one id make the file malformed`() {
        let entry = #"{"id": "E0000000-0000-4000-8000-000000000001", "name": "a", "status": 200, "headers": [], "body": {"text": ""}}"#
        #expect(throws: RequestFileError.malformed("duplicate Example id")) { try RequestFile.decode(Self.file(examples: "[\(entry), \(entry)]")) }
    }
}

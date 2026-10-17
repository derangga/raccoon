import RaccoonDomain
import Testing

struct CurlBodyTests {
    func body(_ flags: String) throws -> Body {
        try CurlImporter.import("curl http://h/ \(flags)").definition.body
    }

    func rows(_ pairs: (String, String)...) -> [Row] {
        pairs.map { Row(name: $0.0, value: $0.1) }
    }

    @Test func `each -F is a text or file Part`() throws {
        #expect(try body("-F 'a=1' -F 'file=@/tmp/a.png;type=image/png' --form 'tok=abc=='") == .multipart([
            Part(name: "a", content: .text("1")),
            Part(name: "file", content: .file(path: "/tmp/a.png")),
            Part(name: "tok", content: .text("abc==")),
        ]))
    }

    @Test func `Chrome's multipart --data-raw is parsed by its boundary`() throws {
        let imported = try CurlImporter.import("""
            curl http://h/ -H 'content-type: multipart/form-data; boundary=----WebKitFormBoundaryX' \
            --data-raw $'------WebKitFormBoundaryX\\r\\nContent-Disposition: form-data; name="a"\\r\\n\\r\\n1\\r\\n\
            ------WebKitFormBoundaryX\\r\\nContent-Disposition: form-data; name="f"; filename="a.png"\\r\\n\
            Content-Type: image/png\\r\\n\\r\\n\\r\\n------WebKitFormBoundaryX--\\r\\n'
            """)
        #expect(imported.definition.body == .multipart([
            Part(name: "a", content: .text("1")),
            Part(name: "f", content: .file(path: "a.png")),
        ]))
        #expect(imported.definition.method == "POST")
    }

    @Test(arguments: [
        ("-d @body.json -H 'Content-Type: application/json'", Body.raw(.json, ""), ["body.json"]),
        ("--data-binary @notes.txt", Body.raw(.text, ""), ["notes.txt"]),
        ("--data @a.xml -H 'Content-Type: text/xml'", Body.raw(.xml, ""), ["a.xml"]),
        ("--data-raw @x", Body.raw(.text, "@x"), []),
    ])
    func `data from @path is a file reference, except for --data-raw`(flags: String, body: Body, fileReferences: [String]) throws {
        let imported = try CurlImporter.import("curl http://h/ \(flags)")
        #expect(imported.definition.body == body)
        #expect(imported.fileReferences == fileReferences)
    }

    @Test(arguments: [
        ("-d 'a=1&b=%20x' -d c", [("a", "1"), ("b", " x"), ("c", "")]),
        ("-H 'Content-Type: application/x-www-form-urlencoded' --data 'a=1'", [("a", "1")]),
        ("--data-urlencode 'a=b&c' -d d=1", [("a", "b&c"), ("d", "1")]),
        ("-d 'a=100%'", [("a", "100%")]),
        ("-d 'a=%E2%9C%93%'", [("a", "✓%")]),
        ("-d 'token=abc=='", [("token", "abc==")]),
        ("-d 'q=a+b'", [("q", "a+b")]),
    ])
    func `form data with no Content-Type is form-urlencoded rows`(flags: String, pairs: [(String, String)]) throws {
        #expect(try body(flags) == .formURLEncoded(pairs.map { Row(name: $0.0, value: $0.1) }))
    }

    @Test(arguments: [
        ("-H 'Content-Type: application/json' -d '{\"a\":1}'", Body.raw(.json, "{\"a\":1}")),
        ("-H 'Content-Type: application/vnd.api+json; charset=utf-8' --data-binary '[]'", Body.raw(.json, "[]")),
        ("-H 'Content-Type: text/xml' --data-raw '<a/>'", Body.raw(.xml, "<a/>")),
        ("-H 'Content-Type: text/plain' -d a -d b", Body.raw(.text, "a&b")),
    ])
    func `json, xml or text data is raw of that kind`(flags: String, body: Body) throws {
        #expect(try self.body(flags) == body)
    }

    @Test(arguments: [
        ("--data-raw 'a=1&b=2'", Body.raw(.text, "a=1&b=2")),
        ("--data-binary 'a=1'", Body.raw(.text, "a=1")),
        ("-H 'Content-Type: application/octet-stream' -d x", Body.raw(.text, "x")),
    ])
    func `any other data is raw text`(flags: String, body: Body) throws {
        #expect(try self.body(flags) == body)
    }

    @Test func `no data is no body, and data without -X is a POST`() throws {
        #expect(try CurlImporter.import("curl http://h/").definition.body == .none)
        #expect(try CurlImporter.import("curl http://h/ -d a=1").definition.method == "POST")
        #expect(try CurlImporter.import("curl http://h/ -F a=1").definition.method == "POST")
        #expect(try CurlImporter.import("curl http://h/ -X GET -d a=1").definition.method == "GET")
    }

    @Test func `-G moves every data value into params`() throws {
        let definition = try CurlImporter.import("curl -G 'http://h/?x=1' -d 'q=a%20b' --data-urlencode 'r=c&d'").definition
        #expect(definition.params == rows(("x", "1"), ("q", "a b"), ("r", "c&d")))
        #expect(definition.body == .none)
        #expect(definition.method == "GET")
    }

    @Test(arguments: [
        ("--json '{\"a\":1}'", [Row(name: "Content-Type", value: "application/json"), Row(name: "Accept", value: "application/json")],
         Body.raw(.json, "{\"a\":1}"), [String]()),
        ("-H 'accept: */*' --json '[]'", [Row(name: "accept", value: "*/*"), Row(name: "Content-Type", value: "application/json")],
         .raw(.json, "[]"), []),
        ("--json @body.json", [Row(name: "Content-Type", value: "application/json"), Row(name: "Accept", value: "application/json")],
         .raw(.json, ""), ["body.json"]),
    ])
    func `--json is a JSON body with its two headers unless -H set them`(flags: String, headers: [Row], body: Body, files: [String]) throws {
        let imported = try CurlImporter.import("curl http://h/ \(flags)")
        #expect(imported.definition.headers == headers)
        #expect(imported.definition.body == body)
        #expect(imported.definition.method == "POST")
        #expect(imported.fileReferences == files)
    }
}

import Foundation
import RaccoonDomain
import Testing

struct SessionFileTests {
    static let saved = RequestDefinition(
        method: "POST", url: "https://api.example.com/charges",
        params: [Row(name: "expand", value: "customer"), Row(name: "debug", value: "1", isEnabled: false)],
        headers: [Row(name: "Idempotency-Key", value: "{{key}}")],
        cookies: [Row(name: "sid", value: "abc")],
        body: .multipart([Part(name: "note", content: .text("hi")), Part(name: "file", isEnabled: false, content: .file(path: "~/a.png"))]),
        auth: .basic(user: "ana", password: "s3cret"),
        settings: RequestSettings(allowsInsecureTLS: true, followsRedirects: true)
    )
    static var edited: RequestDefinition {
        var definition = saved
        definition.body = .raw(.json, #"{"amount": 100}"#)
        definition.auth = .bearer(token: "{{token}}")
        return definition
    }

    static let draftID = TabID(UUID())
    static let session = Session(
        tabs: [
            TabSnapshot(id: draftID, source: .draft, definition: .empty, baseline: nil),
            TabSnapshot(id: TabID(UUID()), source: .request(RequestID(UUID())), definition: edited, baseline: saved),
            TabSnapshot(
                id: TabID(UUID()), source: .draft,
                definition: RequestDefinition(method: "PUT", url: "x", params: [], headers: [], cookies: [],
                                              body: .formURLEncoded([Row(name: "a", value: "b")]), auth: .none,
                                              settings: RequestSettings(allowsInsecureTLS: false, followsRedirects: false)),
                baseline: nil),
        ],
        selected: draftID,
        activeEnvironment: "Prod"
    )

    @Test func `a Session with zero Tabs round-trips as zero Tabs`() throws {
        let empty = Session(tabs: [], selected: nil, activeEnvironment: "Prod")
        #expect(try SessionFile.decode(SessionFile.encode(empty)) == empty)
    }

    @Test func `a Session with a Draft, a Dirty Request Tab and an Active Environment round-trips`() throws {
        #expect(try SessionFile.decode(SessionFile.encode(Self.session)) == Self.session)
    }

    @Test func `no Response is encoded, and the file says version 1`() throws {
        let object = try JSONSerialization.jsonObject(with: SessionFile.encode(Self.session)) as! [String: Any]
        #expect(object["version"] as? Int == 1)
        let tabs = object["tabs"] as! [[String: Any]]
        #expect(tabs.allSatisfy { Set($0.keys).isSubset(of: ["id", "requestID", "definition", "baseline"]) })
    }

    @Test func `a file with only what has no default decodes, absence meaning the defaults`() throws {
        let id = UUID()
        let json = #"{"version": 1, "tabs": [{"id": "\#(id)", "definition": {"method": "GET", "url": "https://a.b", "params": [{"name": "q", "value": "1"}]}}]}"#
        var expected = RequestDefinition.empty
        expected.url = "https://a.b"
        expected.params = [Row(name: "q", value: "1")]
        let session = Session(tabs: [TabSnapshot(id: TabID(id), source: .draft, definition: expected, baseline: nil)],
                              selected: nil, activeEnvironment: nil)
        #expect(try SessionFile.decode(Data(json.utf8)) == session)
    }

    @Test(arguments: [
        "not json at all",
        #"{"version": 2, "tabs": []}"#,
        #"{"tabs": []}"#,
        #"{"version": 1, "tabs": [{"id": "nope", "definition": {"method": "GET", "url": ""}}]}"#,
        #"{"version": 1, "tabs": [{"id": "\#(UUID())", "definition": {"method": "GET", "url": "", "body": {"type": "websocket"}}}]}"#,
        #"{"version": 1, "tabs": [{"id": "\#(UUID())", "definition": {"method": "GET", "url": "", "body": {"type": "raw"}}}]}"#,
    ])
    func `an unknown version or bytes that are not a Session are undecodable`(json: String) {
        #expect {
            try SessionFile.decode(Data(json.utf8))
        } throws: { error in
            if case .undecodable(path: "session.json", _) = error as? StoreError { true } else { false }
        }
    }

    @Test func `a Draft and a Dirty edit carry their Path Variable values through the Session`() throws {
        var saved = Self.saved
        saved.url = "https://h/charges/:id"
        saved.pathVariables = ["id": "7"]
        var edited = saved
        edited.pathVariables["id"] = "8"
        var draft = RequestDefinition.empty
        draft.url = "https://h/:a/:b"
        draft.pathVariables = ["a": "1"]
        let session = Session(tabs: [
            TabSnapshot(id: TabID(UUID()), source: .draft, definition: draft, baseline: nil),
            TabSnapshot(id: TabID(UUID()), source: .request(RequestID(UUID())), definition: edited, baseline: saved),
        ], selected: nil, activeEnvironment: nil)
        #expect(try SessionFile.decode(SessionFile.encode(session)) == session)
    }

    @Test(arguments: [#"["id"]"#, #"{"id": 7}"#])
    func `pathVariables that is not an object of strings leaves the Session undecodable`(value: String) {
        let json = #"{"version": 1, "tabs": [{"id": "\#(UUID())", "definition": {"method": "GET", "url": "", "pathVariables": \#(value)}}]}"#
        #expect {
            try SessionFile.decode(Data(json.utf8))
        } throws: { error in
            if case .undecodable(path: "session.json", _) = error as? StoreError { true } else { false }
        }
    }

    static let example = Example(
        id: ExampleID(UUID()), name: "404 Not Found", status: 404, headers: [Row(name: "Content-Type", value: "application/json")],
        body: .text(#"{"error": "gone"}"#), delayMilliseconds: 250)

    @Test func `a Dirty Example Tab, one on disk and one that is not, round-trip with their content`() throws {
        var edited = Self.example
        edited.name = "Not here"
        edited.body = .bytes(Data([0, 1, 2, 255]))
        let request = RequestID(UUID())
        let session = Session(tabs: [
            TabSnapshot(id: TabID(UUID()), source: .example(request, Self.example.id), content: .example(edited), baseline: .example(Self.example)),
            TabSnapshot(id: TabID(UUID()), source: .example(request, Self.example.id), content: .example(edited), baseline: nil),
        ], selected: nil, activeEnvironment: nil)
        #expect(try SessionFile.decode(SessionFile.encode(session)) == session)
    }

    @Test func `an Example Tab is written as an Example, in the Request file's encoding`() throws {
        let request = RequestID(UUID())
        let session = Session(tabs: [TabSnapshot(
            id: TabID(UUID()), source: .example(request, Self.example.id), content: .example(Self.example), baseline: .example(Self.example))],
            selected: nil, activeEnvironment: nil)
        let tab = try #require((JSONSerialization.jsonObject(with: SessionFile.encode(session)) as! [String: Any])["tabs"] as? [[String: Any]])[0]
        #expect(tab["definition"] == nil)
        #expect(tab["requestID"] as? String == request.rawValue.uuidString)
        #expect(tab["exampleID"] as? String == Self.example.id.rawValue.uuidString)
        let written = try #require(tab["example"] as? [String: Any])
        #expect(written["name"] as? String == "404 Not Found" && written["status"] as? Int == 404 && written["delayMilliseconds"] as? Int == 250)
    }

    @Test(arguments: [
        // an Example source with no Example content
        #"{"version": 1, "tabs": [{"id": "\#(UUID())", "requestID": "\#(UUID())", "exampleID": "\#(UUID())"}]}"#,
        // an Example that does not decode: neither text nor base64
        #"{"version": 1, "tabs": [{"id": "\#(UUID())", "requestID": "\#(UUID())", "exampleID": "\#(UUID())", "example": {"id": "\#(UUID())", "name": "n", "status": 200, "headers": [], "body": {}}}]}"#,
        // an exampleID with no requestID
        #"{"version": 1, "tabs": [{"id": "\#(UUID())", "exampleID": "\#(UUID())", "example": {"id": "\#(UUID())", "name": "n", "status": 200, "headers": [], "body": {"text": ""}}}]}"#,
        // a Request Tab with no definition
        #"{"version": 1, "tabs": [{"id": "\#(UUID())", "requestID": "\#(UUID())"}]}"#,
    ])
    func `an Example Tab without its Example, or a Tab without its definition, leaves the Session undecodable`(json: String) {
        #expect {
            try SessionFile.decode(Data(json.utf8))
        } throws: { error in
            if case .undecodable(path: "session.json", _) = error as? StoreError { true } else { false }
        }
    }
}

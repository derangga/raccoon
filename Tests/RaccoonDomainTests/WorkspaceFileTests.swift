import Foundation
import RaccoonDomain
import Testing

struct WorkspaceFileTests {
    let id = WorkspaceID(UUID(uuidString: "6F9619FF-8B86-D011-B42D-00C04FC964FF")!)

    @Test func `decode of encode is the same id`() throws {
        #expect(try WorkspaceFile.decode(WorkspaceFile.encode(id)) == id)
    }

    @Test func `encode writes the same bytes for the same id`() {
        #expect(WorkspaceFile.encode(id) == WorkspaceFile.encode(id))
        #expect(String(decoding: WorkspaceFile.encode(id), as: UTF8.self) == """
            {
              "id" : "6F9619FF-8B86-D011-B42D-00C04FC964FF",
              "version" : 1
            }

            """)
    }

    // MARK: mocks

    let idLine = #""id": "6F9619FF-8B86-D011-B42D-00C04FC964FF""#

    func mocks(of json: String) throws -> [String: MockSettings] {
        try WorkspaceFile.contents(Data(json.utf8)).mocks
    }

    @Test func `a file without mocks is byte-identical after decode and encode`() throws {
        let bytes = WorkspaceFile.encode(id)
        let decoded = try WorkspaceFile.contents(bytes)
        #expect(decoded.id == id)
        #expect(decoded.mocks.isEmpty)
        #expect(WorkspaceFile.encode(decoded.id, mocks: decoded.mocks) == bytes)
        #expect(!String(decoding: bytes, as: UTF8.self).contains("mocks"))
    }

    @Test func `mocks round-trip with the id and are written in sorted, pretty form`() throws {
        let mocks = [
            "Pets": MockSettings(port: 8080, allowsCORS: false),
            "Shop": MockSettings(port: nil, allowsCORS: true),
        ]
        let bytes = WorkspaceFile.encode(id, mocks: mocks)
        #expect(String(decoding: bytes, as: UTF8.self) == """
            {
              "id" : "6F9619FF-8B86-D011-B42D-00C04FC964FF",
              "mocks" : {
                "Pets" : {
                  "allowsCORS" : false,
                  "port" : 8080
                },
                "Shop" : {
                  "allowsCORS" : true
                }
              },
              "version" : 1
            }

            """)
        let decoded = try WorkspaceFile.contents(bytes)
        #expect(decoded.id == id)
        #expect(decoded.mocks == mocks)
        #expect(try WorkspaceFile.decode(bytes) == id)
    }

    @Test func `a Collection with no entry has no port and allows CORS`() {
        #expect(WorkspaceFile.settings(for: "Pets", in: [:]) == MockSettings(port: nil, allowsCORS: true))
        #expect(WorkspaceFile.settings(for: "Pets", in: ["Shop": MockSettings(port: 1, allowsCORS: false)]) == .standard)
        #expect(WorkspaceFile.settings(for: "Shop", in: ["Shop": MockSettings(port: 1, allowsCORS: false)])
            == MockSettings(port: 1, allowsCORS: false))
    }

    @Test(arguments: [
        (#"{"port": "x"}"#, MockSettings(port: nil, allowsCORS: true)),
        (#"{"port": 70000}"#, MockSettings(port: nil, allowsCORS: true)),
        (#"{"port": -1}"#, MockSettings(port: nil, allowsCORS: true)),
        (#"{"port": 80.5}"#, MockSettings(port: nil, allowsCORS: true)),
        (#"{"port": null}"#, MockSettings(port: nil, allowsCORS: true)),
        (#"{"port": 65535}"#, MockSettings(port: 65535, allowsCORS: true)),
        (#"{"port": 0}"#, MockSettings(port: 0, allowsCORS: true)),
        (#"{"allowsCORS": 1}"#, MockSettings(port: nil, allowsCORS: true)),
        (#"{"allowsCORS": "no"}"#, MockSettings(port: nil, allowsCORS: true)),
        (#"{"allowsCORS": false}"#, MockSettings(port: nil, allowsCORS: false)),
        (#"{"port": "x", "allowsCORS": false}"#, MockSettings(port: nil, allowsCORS: false)),
        (#"{"port": 9000, "allowsCORS": 0}"#, MockSettings(port: 9000, allowsCORS: true)),
        (#"{}"#, MockSettings(port: nil, allowsCORS: true)),
        (#"7"#, MockSettings(port: nil, allowsCORS: true)),
        (#"[]"#, MockSettings(port: nil, allowsCORS: true)),
    ])
    func `a value of the wrong type in an entry is absent`(entry: String, expected: MockSettings) throws {
        let found = try mocks(of: #"{"version": 1, \#(idLine), "mocks": {"A": \#(entry)}}"#)
        #expect(WorkspaceFile.settings(for: "A", in: found) == expected)
    }

    @Test(arguments: [#"[]"#, #""x""#, "3", "null", "true"])
    func `a mocks that is not an object means no settings and the id still decodes`(value: String) throws {
        let decoded = try WorkspaceFile.contents(Data(#"{"version": 1, \#(idLine), "mocks": \#(value)}"#.utf8))
        #expect(decoded.id == id)
        #expect(decoded.mocks.isEmpty)
    }

    @Test func `one Collection's bad entry does not hide another's good one`() throws {
        let found = try mocks(of: #"{"version": 1, \#(idLine), "mocks": {"A": 5, "B": {"port": 9000, "allowsCORS": false}}}"#)
        #expect(WorkspaceFile.settings(for: "A", in: found) == .standard)
        #expect(WorkspaceFile.settings(for: "B", in: found) == MockSettings(port: 9000, allowsCORS: false))
    }

    @Test func `replacing one Collection's settings keeps the id and the other Collections`() throws {
        let start = WorkspaceFile.encode(id, mocks: ["B": MockSettings(port: 9000, allowsCORS: false)])
        let next = try WorkspaceFile.replacing(MockSettings(port: 8080, allowsCORS: true), for: "A", in: start)
        let decoded = try WorkspaceFile.contents(next)
        #expect(decoded.id == id)
        #expect(decoded.mocks == [
            "A": MockSettings(port: 8080, allowsCORS: true),
            "B": MockSettings(port: 9000, allowsCORS: false),
        ])
        let again = try WorkspaceFile.replacing(MockSettings(port: nil, allowsCORS: false), for: "A", in: next)
        #expect(try WorkspaceFile.contents(again).mocks["A"] == MockSettings(port: nil, allowsCORS: false))
    }

    @Test func `replacing in bytes that are not a raccoon file is undecodable`() {
        #expect {
            try WorkspaceFile.replacing(.standard, for: "A", in: Data("not json".utf8))
        } throws: { error in
            if case .undecodable(path: "raccoon.json", _) = error as? StoreError { true } else { false }
        }
    }

    @Test(arguments: [
        #"{"version": 1}"#,
        #"{"version": 1, "id": "not-a-uuid"}"#,
        #"{"version": 2, "id": "6F9619FF-8B86-D011-B42D-00C04FC964FF"}"#,
        #"{"id": "6F9619FF-8B86-D011-B42D-00C04FC964FF"}"#,
        "not json",
        "[]",
    ])
    func `a missing id, an id that is not a UUID, an unknown version or not JSON is undecodable`(json: String) {
        #expect {
            try WorkspaceFile.decode(Data(json.utf8))
        } throws: { error in
            if case .undecodable(path: "raccoon.json", _) = error as? StoreError { true } else { false }
        }
    }
}

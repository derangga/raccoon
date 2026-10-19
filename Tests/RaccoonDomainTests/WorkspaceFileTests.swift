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

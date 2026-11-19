import Foundation
import RaccoonDomain
import Testing

struct ExampleDuplicateTests {
    let original = ExampleID(UUID(uuidString: "00000000-0000-4000-8000-00000000E001")!)
    let copy = ExampleID(UUID(uuidString: "00000000-0000-4000-8000-00000000E002")!)

    @Test(arguments: [("Created", "Created 2"), ("Created 2", "Created 2 2"), ("", " 2")])
    func `the copy's name is the original's with " 2" appended, literally`(name: String, expected: String) {
        let example = Example(id: original, name: name, status: 201, body: .text(""))

        #expect(example.duplicate(id: copy).name == expected)
    }

    @Test func `the copy has the new id and everything else of the original`() {
        let example = Example(
            id: original, name: "Created", status: 402,
            headers: [Row(name: "Content-Type", value: "application/json"), Row(name: "X-Off", value: "1", isEnabled: false)],
            body: .bytes(Data([0xFF, 0x00])), delayMilliseconds: 250)

        let duplicate = example.duplicate(id: copy)

        #expect(duplicate == Example(
            id: copy, name: "Created 2", status: 402,
            headers: [Row(name: "Content-Type", value: "application/json"), Row(name: "X-Off", value: "1", isEnabled: false)],
            body: .bytes(Data([0xFF, 0x00])), delayMilliseconds: 250))
        #expect(example.id == original)
    }
}

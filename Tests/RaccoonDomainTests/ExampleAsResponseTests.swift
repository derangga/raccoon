import Foundation
import RaccoonDomain
import Testing

/// Showing an Example in the Response viewer (examples.md §Show an Example).
struct ExampleAsResponseTests {
    let id = ExampleID(UUID())

    @Test func `a text Example is its status, its enabled headers and its UTF-8 bytes, with nothing measured`() {
        let example = Example(
            id: id, name: "ok", status: 201,
            headers: [Row(name: "Content-Type", value: "application/json"), Row(name: "X-Off", value: "no", isEnabled: false)],
            body: .text(#"{"ok":true}"#), delayMilliseconds: 500)

        let response = example.asResponse

        #expect(response == Response(
            status: 201, headers: [.init(name: "Content-Type", value: "application/json")],
            body: Data(#"{"ok":true}"#.utf8), elapsed: .zero, byteCount: 11))
    }

    @Test func `a bytes Example keeps its bytes and counts them`() {
        let bytes = Data([0xFF, 0xFE, 0x00, 0x81])

        let response = Example(id: id, name: "bin", status: 200, body: .bytes(bytes)).asResponse

        #expect(response.body == bytes)
        #expect(response.byteCount == 4)
    }
}

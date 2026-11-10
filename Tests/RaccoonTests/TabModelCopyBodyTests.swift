import Foundation
@testable import Raccoon
import RaccoonDomain
import RaccoonTesting
import Testing

@MainActor
struct TabModelCopyBodyTests {
    func response(_ text: String) -> Response {
        Response(status: 200, headers: [], body: Data(text.utf8), elapsed: .milliseconds(5), byteCount: text.utf8.count)
    }

    @Test func `the shown text is Pretty in Pretty and the bytes as text in Raw`() async {
        let raw = #"{"a":{"b":1}}"#
        let presented = await TabModel.present(response(raw))
        let pretty = TabModel.shownText(response(raw), presented, pretty: true)
        #expect(pretty.contains("\n"))
        #expect(pretty.contains(#""b": 1"#))
        #expect(TabModel.shownText(response(raw), presented, pretty: false) == raw)
    }

    @Test func `before the presentation lands the shown text is the bytes as text`() {
        #expect(TabModel.shownText(response("plain"), nil, pretty: true) == "plain")
    }

    @Test func `a binary body's shown text is its Hex view`() async {
        let bytes = Response(status: 200, headers: [], body: Data([0xFF, 0x00]), elapsed: .zero, byteCount: 2)
        let presented = await TabModel.present(bytes)
        #expect(TabModel.shownText(bytes, presented, pretty: true) == presented.hex?.text)
    }

    @Test func `Copy writes the shown text, and nothing without a received Response`() {
        let clipboard = RecordingClipboardWriter()
        let model = TabModel(transport: ScriptedTransport(.failure(.timedOut(seconds: 60))), secrets: InMemorySecretStore(),
                             files: DictionaryFileReading([:]), instants: FixedInstantSource(.now), clipboard: clipboard)
        model.copyBody(pretty: true)
        #expect(clipboard.string == nil)

        model.tab.response = .received(response("hello"))
        model.copyBody(pretty: true)
        #expect(clipboard.string == "hello")
    }
}

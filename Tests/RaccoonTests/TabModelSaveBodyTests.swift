import Foundation
@testable import Raccoon
import RaccoonDomain
import RaccoonTesting
import Testing

@MainActor
struct TabModelSaveBodyTests {
    let now = ContinuousClock.now
    /// A 1 × 1 PNG, so ImageIO decodes it.
    let png = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==")!

    func response(_ body: Data, headers: [Response.Header] = [], byteCount: Int? = nil) -> Response {
        Response(status: 200, headers: headers, body: body, elapsed: .milliseconds(5), byteCount: byteCount ?? body.count)
    }

    func tab(_ state: ResponseState) -> TabModel {
        let model = TabModel(transport: ScriptedTransport(.failure(.timedOut(seconds: 60))), secrets: InMemorySecretStore(), files: DictionaryFileReading([:]), instants: FixedInstantSource(now), clipboard: RecordingClipboardWriter())
        model.tab.response = state
        return model
    }

    // MARK: Presented.hex

    @Test func `a binary body presents its Hex view`() async {
        let bytes = Data([0xFF, 0xFE, 0x00, 0x81])
        let presented = await TabModel.present(response(bytes))
        #expect(presented.body == .binary(byteCount: 4))
        #expect(presented.hex == HexDump(bytes))
        #expect(presented.hex?.text == "00000000  ff fe 00 81                                       |....|\n00000004")
    }

    @Test func `a text body presents no Hex view`() async {
        #expect(await TabModel.present(response(Data(#"{"a":1}"#.utf8))).hex == nil)
    }

    @Test func `an image ImageIO decodes presents no Hex view, so it never pays for one`() async {
        let image = response(png, headers: [.init(name: "Content-Type", value: "image/png")])
        let presented = await TabModel.present(image)
        #expect(presented.body == .image(mediaType: "image/png"))
        #expect(presented.hex == nil)
    }

    @Test func `an image ImageIO cannot decode presents its Hex view, so the reason is visible`() async {
        let broken = Data("not a picture".utf8)
        let presented = await TabModel.present(response(broken, headers: [.init(name: "Content-Type", value: "image/png")]))
        #expect(presented.body == .image(mediaType: "image/png"))
        #expect(presented.hex == HexDump(broken))
    }

    @Test func `a truncated image with a valid header presents its Hex view, as NSImage will not draw it`() async {
        let truncated = png.prefix(40)
        let presented = await TabModel.present(response(truncated, headers: [.init(name: "Content-Type", value: "image/png")]))
        #expect(presented.hex == HexDump(truncated))
    }

    @Test func `a binary body over the limit presents the first MB and counts the rest`() async {
        let presented = await TabModel.present(response(Data(repeating: 0xFF, count: HexDump.limit + 1)))
        #expect(presented.hex?.shownBytes == HexDump.limit)
        #expect(presented.hex?.totalBytes == HexDump.limit + 1)
    }

    // MARK: Save Response Body

    @Test(arguments: [
        ResponseState.idle, .sending(since: ContinuousClock.now), .failed(.timedOut(seconds: 60), after: .zero), .notSent(.invalidURL("x")),
    ])
    func `nothing is saved without a received Response`(state: ResponseState) throws {
        let model = tab(state)
        #expect(!model.canSaveBody)
        let writer = RecordingFileWriting()
        #expect(model.bodyToSave == nil)
        #expect(writer.writes.isEmpty)
    }

    @Test func `a received Response with bytes can be saved, an empty one cannot`() {
        #expect(tab(.received(response(Data("x".utf8)))).canSaveBody)
        #expect(!tab(.received(response(Data()))).canSaveBody)
    }

    @Test func `the bytes written are the bytes the viewer holds, exactly`() throws {
        let bytes = Data([0x00, 0xFF, 0xFE, 0x0A, 0x80])
        let writer = RecordingFileWriting()
        let target = URL(filePath: "/tmp/picked/out.bin")

        try tab(.received(response(bytes))).bodyToSave?.write(to: target, writer: writer)

        #expect(writer.writes.map(\.url) == [target])
        #expect(writer.writes.map(\.data) == [bytes])
    }

    @Test func `an unwritable target surfaces to the caller with its path`() {
        let target = URL(filePath: "/tmp/picked/out.bin")
        let failure = StoreError.unwritable(path: target.path, reason: "Permission denied")
        let writer = RecordingFileWriting(failing: [target: failure])

        #expect(throws: failure) { try tab(.received(response(Data("x".utf8)))).bodyToSave?.write(to: target, writer: writer) }
        #expect(writer.writes.isEmpty)
    }

    @Test func `the offered name comes from the Response's headers`() {
        let headers = [Response.Header(name: "Content-Disposition", value: #"attachment; filename="r.pdf""#)]
        #expect(tab(.received(response(Data("x".utf8), headers: headers))).bodyToSave?.name == "r.pdf")
        #expect(tab(.received(response(Data("x".utf8)))).bodyToSave?.name == "response")
        #expect(tab(.idle).bodyToSave?.name == nil)
    }

    @Test func `with no Content-Disposition the offered name is the last URL's, after redirects`() {
        var redirected = response(Data("x".utf8))
        redirected.url = URL(string: "https://a.example/files/report.csv")
        #expect(tab(.received(redirected)).bodyToSave?.name == "report.csv")
    }
}

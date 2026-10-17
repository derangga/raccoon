import AppKit
import Foundation
@testable import Raccoon
import RaccoonDomain
import RaccoonTesting
import Testing

@MainActor
struct ResponseViewerTests {
    let theme = ThemeEnvironment(catalog: ThemeCatalog.load(), isDark: false)
    let now = ContinuousClock.now
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 520, height: 300), styleMask: [], backing: .buffered, defer: false)

    func response(_ body: Data, status: Int = 200) -> Response {
        Response(status: status, headers: [], body: body, elapsed: .milliseconds(184), byteCount: body.count)
    }

    /// A Tab that has received `response` and finished presenting it.
    func received(_ response: Response) async -> (TabModel, ResponseViewer) {
        let model = TabModel(transport: ScriptedTransport(.success(response)), secrets: InMemorySecretStore(), files: DictionaryFileReading([:]), instants: FixedInstantSource(now))
        model.tab.definition.url = "http://localhost/"
        model.send()
        await model.inFlight?.value
        await model.presenting?.value
        return (model, viewer(model))
    }

    func viewer(_ model: TabModel) -> ResponseViewer {
        let viewer = ResponseViewer(model: model, theme: theme)
        viewer.frame = window.contentView!.bounds
        window.contentView!.addSubview(viewer)
        viewer.layoutSubtreeIfNeeded()
        return viewer
    }

    @Test func `idle says how to send, with the key cap`() {
        let model = TabModel(transport: ScriptedTransport(.failure(.timedOut)), secrets: InMemorySecretStore(), files: DictionaryFileReading([:]), instants: FixedInstantSource(now))
        let viewer = viewer(model)
        #expect(viewer.voidText.stringValue == "Send a request to see the Response here.")
        #expect(!viewer.keycap.isHidden && viewer.keycap.stringValue == "⌘↩")
        #expect(viewer.codeLabel.stringValue == "")
    }

    @Test func `sending shows nothing for 150 ms, then the spinner and the live time`() {
        let model = TabModel(transport: ScriptedTransport(.failure(.timedOut)), secrets: InMemorySecretStore(), files: DictionaryFileReading([:]), instants: FixedInstantSource(now))
        model.tab.response = .sending(since: now - .milliseconds(100))
        let early = viewer(model)
        #expect(early.codeLabel.stringValue == "" && early.voidText.stringValue == "")

        model.tab.response = .sending(since: now - .milliseconds(1_440))
        let later = viewer(model)
        #expect(later.codeLabel.stringValue == "Sending…")
        #expect(later.elapsedLabel.stringValue == "1.4 s")
        #expect(later.elapsedLabel.font == .monospacedDigitSystemFont(ofSize: 12, weight: .regular))
        #expect(later.voidText.stringValue == "Waiting for the server. ⌘. cancels.")
    }

    @Test func `a JSON body is shown Pretty and colored, and Raw on demand`() async {
        let (_, viewer) = await received(response(Data(#"{"a":1}"#.utf8)))
        #expect(viewer.codeLabel.stringValue == "200" && viewer.reasonLabel.stringValue == "OK")
        #expect(viewer.elapsedLabel.stringValue == "184 ms" && viewer.sizeLabel.stringValue == "7 B")
        #expect(viewer.mode.isEnabled(forSegment: 0) && viewer.mode.selectedSegment == 0)
        let text = viewer.textView.textStorage!
        #expect(text.string == "{\n  \"a\": 1\n}")
        #expect(text.attribute(.foregroundColor, at: 4, effectiveRange: nil) as? NSColor == theme.color(.jsonKey))

        viewer.mode.selectedSegment = 1
        viewer.mode.sendAction(viewer.mode.action, to: viewer.mode.target)
        #expect(viewer.textView.textStorage!.string == #"{"a":1}"#)
    }

    @Test func `Raw shows first, and Pretty takes over once the presentation lands`() async {
        let model = TabModel(transport: ScriptedTransport(.success(response(Data(#"{"a":1}"#.utf8)))), secrets: InMemorySecretStore(), files: DictionaryFileReading([:]),
                             instants: FixedInstantSource(now))
        model.tab.definition.url = "http://localhost/"
        let viewer = viewer(model)
        model.send()
        await model.inFlight?.value
        viewer.render()
        #expect(viewer.textView.textStorage!.string == #"{"a":1}"#)

        await model.presenting?.value
        viewer.render()
        #expect(viewer.mode.selectedSegment == 0)
        #expect(viewer.textView.textStorage!.string == "{\n  \"a\": 1\n}")
    }

    @Test func `a body that does not parse is Raw with Pretty unavailable`() async {
        let (_, viewer) = await received(response(Data("<html><p>Hi<br></html>".utf8)))
        #expect(!viewer.mode.isEnabled(forSegment: 0) && viewer.mode.selectedSegment == 1)
        #expect(viewer.textView.textStorage!.string == "<html><p>Hi<br></html>")
        #expect(viewer.prettyNote.isHidden)
    }

    @Test func `above the threshold Pretty is off and says why`() async {
        let big = Data(("[" + String(repeating: " ", count: ResponseBody.prettyThreshold) + "]").utf8)
        let (_, viewer) = await received(response(big))
        #expect(!viewer.mode.isEnabled(forSegment: 0))
        #expect(!viewer.prettyNote.isHidden && viewer.prettyNote.stringValue == "Pretty is off above 5 MB")
        #expect(viewer.textView.textContainer?.widthTracksTextView == false)
    }

    @Test func `a binary body says so instead of drawing bytes`() async {
        let (_, viewer) = await received(response(Data([0xFF, 0xFE, 0x00, 0x81])))
        #expect(viewer.voidTitle.stringValue == "Binary body")
        #expect(viewer.voidText.stringValue == "4 B that is not UTF-8 text. Raccoon shows text bodies only.")
    }

    @Test func `an empty body says so, and the status line stays`() async {
        let (_, viewer) = await received(response(Data(), status: 204))
        #expect(viewer.voidText.stringValue == "Empty body.")
        #expect(viewer.codeLabel.stringValue == "204" && viewer.sizeLabel.stringValue == "0 B")
    }

    @Test func `only the reason truncates, never the code, time or size`() async {
        let (_, viewer) = await received(response(Data("x".utf8), status: 511))
        #expect(viewer.reasonLabel.stringValue == "Network Authentication Required")
        #expect(viewer.reasonLabel.lineBreakMode == .byTruncatingTail)
        let low = viewer.reasonLabel.contentCompressionResistancePriority(for: .horizontal)
        for label in [viewer.codeLabel, viewer.elapsedLabel, viewer.sizeLabel] {
            #expect(label.contentCompressionResistancePriority(for: .horizontal) > low)
        }
    }

    func failed(_ error: SendError, after: Duration) -> (ScriptedTransport, TabModel, ResponseViewer) {
        let transport = ScriptedTransport(.failure(error))
        let model = TabModel(transport: transport, secrets: InMemorySecretStore(), files: DictionaryFileReading([:]), instants: FixedInstantSource(now))
        model.tab.response = .failed(error, after: after)
        return (transport, model, viewer(model))
    }

    @Test func `an untrusted certificate names the host and offers the one fix, which sends nothing`() {
        let host = "grafana.staging.internal.example.com"
        let (transport, model, viewer) = failed(.untrustedCertificate(host: host), after: .milliseconds(212))
        #expect(viewer.codeLabel.stringValue == "Failed" && viewer.elapsedLabel.stringValue == "after 212 ms")
        #expect(viewer.codeLabel.textColor == theme.color(.statusFailed) && !viewer.elapsedLabel.isHidden)
        #expect(!viewer.failureGlyph.isHidden)
        #expect(viewer.voidTitle.stringValue == "Untrusted certificate" && viewer.voidTitle.textColor == theme.color(.statusFailed))
        #expect(viewer.voidText.stringValue == "The certificate for \(host) is not trusted by this Mac. It may be self-signed or expired.")
        #expect(!viewer.fixButton.isHidden && viewer.fixButton.title == "Allow insecure TLS for this request")

        viewer.fixButton.performClick(nil)

        #expect(model.tab.definition.settings.allowsInsecureTLS)
        #expect(transport.requests.isEmpty)
    }

    @Test(arguments: [
        (SendError.timedOut, Duration.seconds(60), "after 60.0 s", "No response after 60 s",
         "The server did not answer in time. Raccoon does not send again by itself."),
        (.transport(.cannotConnectToHost, "Could not connect to the server.", host: "localhost:8080"), .milliseconds(3), "after 3 ms",
         "Could not connect to the server", "NSURLErrorCannotConnectToHost (−1004) · localhost:8080"),
    ])
    func `other failures show title and detail, never the TLS button`(
        error: SendError, after: Duration, elapsed: String, title: String, detail: String
    ) {
        let (_, _, viewer) = failed(error, after: after)
        #expect(viewer.codeLabel.stringValue == "Failed" && viewer.elapsedLabel.stringValue == elapsed)
        #expect(viewer.voidTitle.stringValue == title && viewer.voidText.stringValue == detail)
        #expect(viewer.fixButton.isHidden && !viewer.failureGlyph.isHidden)
    }

    @Test func `an invalid URL is Not sent and quotes the URL after substitution`() {
        let model = TabModel(transport: ScriptedTransport(.failure(.timedOut)), secrets: InMemorySecretStore(), files: DictionaryFileReading([:]), instants: FixedInstantSource(now))
        model.tab.definition.url = "https//api.dev.example.com/v1"
        model.send()
        let viewer = viewer(model)
        #expect(viewer.codeLabel.stringValue == "Not sent" && viewer.elapsedLabel.isHidden)
        #expect(viewer.voidTitle.stringValue == "Invalid URL")
        #expect(viewer.voidText.stringValue == "After substitution the URL was https//api.dev.example.com/v1.")
        #expect(viewer.fixButton.isHidden)
    }

    @Test func `idle shows no failure glyph`() {
        let model = TabModel(transport: ScriptedTransport(.failure(.timedOut)), secrets: InMemorySecretStore(), files: DictionaryFileReading([:]), instants: FixedInstantSource(now))
        #expect(viewer(model).failureGlyph.isHidden)
    }

    func showHeaders(_ viewer: ResponseViewer) {
        viewer.section.selectedSegment = 1
        viewer.section.sendAction(viewer.section.action, to: viewer.section.target)
    }

    @Test func `Headers shows one row per header, sorted as received, with the merged-headers note`() async {
        // URLSession has already joined the two Set-Cookie headers and sorted by name.
        let headers = [
            Response.Header(name: "Content-Length", value: "0"),
            Response.Header(name: "Location", value: "https://payments.example.com/v2/charges"),
            Response.Header(name: "Set-Cookie", value: "session=7f3a; Path=/; HttpOnly, locale=en; Path=/"),
        ]
        let (_, viewer) = await received(Response(status: 301, headers: headers, body: Data(), elapsed: .milliseconds(55), byteCount: 0))
        #expect(viewer.section.label(forSegment: 0) == "Body" && viewer.section.label(forSegment: 1) == "Headers 3")
        #expect(viewer.section.selectedSegment == 0 && viewer.headerList.isHidden)

        showHeaders(viewer)
        #expect(!viewer.headerList.isHidden && viewer.voidStack.isHidden && viewer.mode.isHidden)
        #expect(viewer.headerRows.map { [$0.name.stringValue, $0.value.stringValue] } == headers.map { [$0.name, $0.value] })
        #expect(viewer.headerNote.stringValue == "macOS merges repeated headers and doesn't keep their order.")
        #expect(!viewer.headerNote.isHidden)

        // Names share one left edge and values another: nothing is centered.
        viewer.frame = NSRect(x: 0, y: 0, width: 800, height: 400)
        viewer.layoutSubtreeIfNeeded()
        let names = viewer.headerRows.map { viewer.convert(NSPoint.zero, from: $0.name).x }
        let values = viewer.headerRows.map { viewer.convert(NSPoint.zero, from: $0.value).x }
        #expect(Set(names).count == 1 && Set(values).count == 1)
        #expect(values[0] - names[0] == 220)
    }

    @Test func `a header value end-truncates with the full value in its tooltip`() async {
        let long = String(repeating: "a", count: 400)
        let (_, viewer) = await received(Response(status: 200, headers: [.init(name: "X-Long", value: long)], body: Data(), elapsed: .zero, byteCount: 0))
        showHeaders(viewer)
        let row = try! #require(viewer.headerRows.first)
        #expect(row.value.lineBreakMode == .byTruncatingTail && row.value.toolTip == long)
        #expect(row.name.textColor == theme.color(.textSecondary) && row.value.textColor == theme.color(.text))
    }

    @Test func `no headers says so, and the note stays`() async {
        let (_, viewer) = await received(response(Data("x".utf8)))
        #expect(viewer.section.label(forSegment: 1) == "Headers 0")
        showHeaders(viewer)
        #expect(viewer.headerRows.isEmpty && viewer.noHeaders.stringValue == "No headers." && !viewer.noHeaders.isHidden)
        #expect(!viewer.headerNote.isHidden)
    }

    @Test func `drawing the same Response again keeps its text storage`() async {
        let (_, viewer) = await received(response(Data(#"{"a":1}"#.utf8)))
        let storage = viewer.textView.textStorage
        viewer.render()
        #expect(viewer.textView.textStorage === storage)
    }
}

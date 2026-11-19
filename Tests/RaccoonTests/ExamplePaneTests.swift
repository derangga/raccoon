import AppKit
@testable import Raccoon
import RaccoonDomain
import RaccoonTesting
import Testing

/// The Example pane: the header row, the Section bar, Headers, the text body and the Hex view,
/// drawn from the bound Tab's Example and writing back through its edit methods.
@MainActor
struct ExamplePaneTests {
    let theme = ThemeEnvironment(catalog: ThemeCatalog.load(), isDark: false)
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 500), styleMask: [], backing: .buffered, defer: false)
    let request = RequestID(UUID())

    func example(
        _ name: String = "ok", status: Int = 200, headers: [Row] = [Row(name: "Content-Type", value: "application/json")],
        body: ExampleBody = .text(#"{"a": 1}"#), delay: Int = 0
    ) -> Example {
        Example(id: ExampleID(UUID()), name: name, status: status, headers: headers, body: body, delayMilliseconds: delay)
    }

    func model(_ example: Example, files: [String: Data] = [:]) -> TabModel {
        let model = TabModel(
            transport: ScriptedTransport(.failure(.timedOut(seconds: 60))), secrets: InMemorySecretStore(),
            files: DictionaryFileReading(files), instants: FixedInstantSource(.now), clipboard: RecordingClipboardWriter())
        model.tab = Tab(id: TabID(UUID()), source: .example(request, example.id), content: .example(example), baseline: .example(example))
        return model
    }

    func pane(_ model: TabModel) -> ExamplePane {
        let pane = ExamplePane(model: model, theme: theme)
        pane.frame = window.contentView!.bounds
        window.contentView!.addSubview(pane)
        pane.layoutSubtreeIfNeeded()
        return pane
    }

    func end(_ field: NSTextField, in pane: ExamplePane, typing text: String) {
        field.stringValue = text
        pane.controlTextDidEndEditing(Notification(name: NSControl.textDidEndEditingNotification, object: field))
    }

    // MARK: Header row

    @Test func `the header row shows the name, the Status with its reason phrase, and the Delay`() {
        let pane = pane(model(example("created", status: 201, delay: 250)))
        #expect(pane.nameField.stringValue == "created")
        #expect(pane.statusLabel.stringValue == "Status" && pane.statusField.stringValue == "201")
        #expect(pane.reasonLabel.stringValue == "Created")
        #expect(pane.delayLabel.stringValue == "Delay" && pane.delayField.stringValue == "250")
        #expect(pane.unitLabel.stringValue == "ms")
    }

    @Test func `the header row is 44 pt high with 12 pt side padding, and its number fields are 64 pt wide`() {
        let pane = pane(model(example()))
        #expect(pane.headerRow.frame.height == 44)
        #expect(pane.nameField.convert(pane.nameField.bounds, to: pane).minX >= 12)
        #expect(pane.msEnd <= pane.bounds.width - 12)
        #expect(pane.statusField.frame.width == 64 && pane.delayField.frame.width == 64)
    }

    @Test func `the reason phrase and the labels are in textTertiary`() {
        let pane = pane(model(example()))
        #expect(pane.reasonLabel.textColor == theme.color(.textTertiary))
    }

    @Test func `a status with no registered reason shows none`() {
        #expect(pane(model(example(status: 599))).reasonLabel.stringValue == "")
    }

    // MARK: Commit

    @Test func `a status typed out of range is clamped when the field ends editing, and the field shows what was kept`() {
        for (typed, kept, reason) in [("700", "599", ""), ("20", "100", "Continue"), ("404", "404", "Not Found")] {
            let model = model(example())
            let pane = pane(model)
            end(pane.statusField, in: pane, typing: typed)
            #expect(model.tab.example?.status == Int(kept))
            #expect(pane.statusField.stringValue == kept)
            #expect(pane.reasonLabel.stringValue == reason)
        }
    }

    @Test func `a delay typed out of range is clamped when the field ends editing`() {
        let model = model(example())
        let pane = pane(model)
        end(pane.delayField, in: pane, typing: "70000")
        #expect(model.tab.example?.delayMilliseconds == 60_000)
        #expect(pane.delayField.stringValue == "60000")
    }

    @Test func `an empty or oversized number is read as nothing or as the top of the range`() {
        let model = model(example(status: 404, delay: 5))
        let pane = pane(model)
        end(pane.statusField, in: pane, typing: "")
        end(pane.delayField, in: pane, typing: "99999999999999999999999")
        #expect(model.tab.example?.status == 404)
        #expect(model.tab.example?.delayMilliseconds == 60_000)
        #expect(pane.statusField.stringValue == "404")
    }

    @Test func `the name is written when its field ends editing`() {
        let model = model(example())
        let pane = pane(model)
        end(pane.nameField, in: pane, typing: "renamed")
        #expect(model.tab.example?.name == "renamed")
        #expect(model.tab.isDirty)
    }

    @Test func `Esc leaves the Example as it was and redraws the field`() {
        let model = model(example(status: 200))
        let pane = pane(model)
        pane.statusField.stringValue = "500"
        #expect(pane.control(pane.statusField, textView: NSTextView(), doCommandBy: #selector(NSResponder.cancelOperation(_:))))
        pane.controlTextDidEndEditing(Notification(name: NSControl.textDidEndEditingNotification, object: pane.statusField))
        #expect(model.tab.example?.status == 200)
        #expect(pane.statusField.stringValue == "200")
    }

    @Test func `the pane redraws when the Tab's Example changes`() {
        let model = model(example())
        let pane = pane(model)
        model.setExampleStatus(404)
        model.setExampleName("gone")
        pane.render()
        #expect(pane.statusField.stringValue == "404" && pane.reasonLabel.stringValue == "Not Found" && pane.nameField.stringValue == "gone")
    }

    // MARK: Section bar and Headers

    @Test func `the Section bar is Headers with its count, then Body`() {
        let rows = [Row(name: "A", value: "1"), Row(name: "B", value: "2", isEnabled: false)]
        #expect(ExampleSection.allCases.map { $0.title(in: example(headers: rows)) } == ["Headers 2", "Body"])
        #expect(ExampleSection.allCases.map { $0.title(in: example(headers: [])) } == ["Headers", "Body"])
        let pane = pane(model(example(headers: rows)))
        #expect(pane.sectionButton(.headers).accessibilityLabel() == "Headers 2")
    }

    @Test func `picking a section shows only its pane`() {
        let pane = pane(model(example()))
        #expect(pane.selected == .body)
        #expect(pane.headersTable.isHiddenOrHasHiddenAncestor && !pane.bodyEditor.isHiddenOrHasHiddenAncestor)
        pane.select(.headers)
        #expect(!pane.headersTable.isHiddenOrHasHiddenAncestor && pane.bodyEditor.isHiddenOrHasHiddenAncestor)
    }

    @Test func `the Headers table shows the Example's headers and writes edits back`() {
        let model = model(example(headers: [Row(name: "X-A", value: "1")]))
        let pane = pane(model)
        #expect(pane.headersTable.rows == [Row(name: "X-A", value: "1")])
        pane.headersTable.onChange([Row(name: "X-A", value: "2")])
        #expect(model.tab.example?.headers == [Row(name: "X-A", value: "2")])
    }

    // MARK: Body

    @Test func `a text body is coloured by the Content-Type, JSON, XML or plain`() {
        for (type, syntax) in [("application/json", BodySyntax.raw(.json)), ("application/atom+xml", .raw(.xml)), ("text/plain", .raw(.text))] {
            let pane = pane(model(example(headers: [Row(name: "Content-Type", value: type)])))
            #expect(pane.bodyEditor.syntax == syntax)
        }
        #expect(pane(model(example(headers: []))).bodyEditor.syntax == .raw(.text))
    }

    @Test func `a new Content-Type recolours the body`() {
        let model = model(example(headers: []))
        let pane = pane(model)
        model.setExampleHeaders([Row(name: "content-type", value: "application/json")])
        pane.render()
        #expect(pane.bodyEditor.syntax == .raw(.json))
    }

    @Test func `a text body shows its text, writes edits back as text, and has no Hex view`() {
        let model = model(example(body: .text("hello")))
        let pane = pane(model)
        #expect(pane.bodyEditor.textView.string == "hello")
        #expect(!pane.bodyEditor.isHidden && pane.hexView.isHidden)
        pane.bodyEditor.onChange("hello world")
        #expect(model.tab.example?.body == .text("hello world"))
    }

    @Test func `a Variable in a body is left as it is written`() {
        let pane = pane(model(example(body: .text("{{token}}"))))
        #expect(!pane.bodyEditor.highlightsVariables)
    }

    @Test func `a bytes body is the Hex view with Replace from File and Save Body, and no editor`() {
        let bytes = Data([0xFF, 0xFE, 0x00, 0x81])
        let pane = pane(model(example(body: .bytes(bytes))))
        #expect(pane.bodyEditor.isHidden && !pane.hexView.isHidden)
        #expect(pane.hexView.textView.string == HexDump(bytes).text)
        #expect(pane.hexView.textView.isEditable == false)
        #expect(pane.hexView.replaceButton.title == "Replace from File…")
        #expect(pane.hexView.saveButton.title == "Save Body…")
        #expect(pane.hexView.limitNote.isHidden && pane.hexView.errorNote.isHidden)
    }

    @Test func `the Body toolbar is 38 pt high`() {
        let pane = pane(model(example(body: .bytes(Data([1])))))
        #expect(pane.hexView.toolbar.frame.height == 38)
    }

    @Test func `a bytes body over the limit says how much of it the Hex view shows`() {
        let pane = pane(model(example(body: .bytes(Data(repeating: 0xFF, count: 1_500_000)))))
        #expect(pane.hexView.limitNote.stringValue == "Showing the first 1 MB of 1.5 MB")
        #expect(!pane.hexView.limitNote.isHidden)
    }

    // MARK: Replace from File…

    @Test func `a text file replaces a bytes body and turns the pane into the editor`() {
        let model = model(example(body: .bytes(Data([0xFF]))), files: ["/a.json": Data(#"{"b":2}"#.utf8)])
        let pane = pane(model)
        pane.replace(fromFile: "/a.json")
        pane.render()
        #expect(model.tab.example?.body == .text(#"{"b":2}"#))
        #expect(!pane.bodyEditor.isHidden && pane.hexView.isHidden)
        #expect(pane.bodyEditor.textView.string == #"{"b":2}"#)
    }

    @Test func `a binary file replaces the bytes and keeps the Hex view`() {
        let png = Data([0x89, 0x50, 0xFF])
        let model = model(example(body: .bytes(Data([0xFF]))), files: ["/a.png": png])
        let pane = pane(model)
        pane.replace(fromFile: "/a.png")
        pane.render()
        #expect(model.tab.example?.body == .bytes(png))
        #expect(pane.hexView.textView.string == HexDump(png).text)
    }

    @Test func `a file that does not read leaves the body and says why in the toolbar`() {
        let original = ExampleBody.bytes(Data([0xFF]))
        let model = model(example(body: original))
        let pane = pane(model)
        pane.replace(fromFile: "/missing")
        #expect(model.tab.example?.body == original)
        #expect(!model.tab.isDirty)
        #expect(!pane.hexView.errorNote.isHidden)
        #expect(pane.hexView.errorNote.stringValue == "Couldn't replace the body: No such file.")
        #expect(pane.hexView.errorNote.textColor == theme.color(.error))
    }

    @Test func `the note goes with the next successful replace`() {
        let model = model(example(body: .bytes(Data([0xFF]))), files: ["/a": Data([0xFE])])
        let pane = pane(model)
        pane.replace(fromFile: "/missing")
        pane.replace(fromFile: "/a")
        pane.render()
        #expect(pane.hexView.errorNote.isHidden)
    }

    // MARK: Tabs

    @Test func `each Tab shows its own Example and keeps its own section`() {
        let first = model(example("one", body: .text("1")))
        let second = model(example("two", body: .text("2")))
        let pane = pane(first)
        pane.select(.headers)

        pane.bind(second)
        #expect(pane.nameField.stringValue == "two" && pane.bodyEditor.textView.string == "2")
        #expect(pane.selected == .body)

        pane.bind(first)
        #expect(pane.nameField.stringValue == "one")
        #expect(pane.selected == .headers)
    }

    @Test func `edits after a switch go to the Tab now shown`() {
        let first = model(example("one"))
        let second = model(example("two"))
        let pane = pane(first)
        pane.bind(second)
        end(pane.nameField, in: pane, typing: "renamed")
        #expect(second.tab.example?.name == "renamed" && first.tab.example?.name == "one")
    }
}

private extension ExamplePane {
    /// Where the last control of the header row ends, in the pane's coordinates.
    var msEnd: CGFloat {
        // The stack places alignment rects: a text field's frame reaches 2 pt past its text.
        unitLabel.alignmentRect(forFrame: unitLabel.convert(unitLabel.bounds, to: self)).maxX
    }
}

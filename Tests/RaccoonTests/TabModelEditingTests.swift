import Foundation
@testable import Raccoon
import RaccoonDomain
import RaccoonTesting
import Testing

@MainActor
struct TabModelEditingTests {
    let model = TabModel(transport: ScriptedTransport(.failure(.timedOut)), secrets: InMemorySecretStore(), files: DictionaryFileReading([:]), instants: FixedInstantSource(.now), clipboard: RecordingClipboardWriter())

    @Test func `typing a query fills the Params table`() {
        model.typeInURLBar("https://api.example.com/v1?a=1&b=2")
        #expect(model.tab.definition.url == "https://api.example.com/v1")
        #expect(model.tab.definition.params == [Row(name: "a", value: "1"), Row(name: "b", value: "2")])
        #expect(model.urlText == "https://api.example.com/v1?a=1&b=2")
    }

    @Test func `a Disabled Row survives typing in the URL bar`() {
        model.tab.definition.params = [Row(name: "a", value: "1"), Row(name: "since", value: "x", isEnabled: false)]
        model.typeInURLBar("https://api.exampl.com?a=2")
        #expect(model.tab.definition.params == [Row(name: "a", value: "2"), Row(name: "since", value: "x", isEnabled: false)])
    }

    @Test func `editing a Params row changes the URL text`() {
        model.typeInURLBar("https://h/?a=1")
        model.tab.definition.params[0].value = "{{id}}"
        #expect(model.urlText == "https://h/?a={{id}}")
    }

    @Test func `a URL edit clears a note but not an error`() {
        model.message = .note("Ignored: -s")
        model.typeInURLBar("h")
        #expect(model.message == nil)
        model.message = .error("No URL in this curl command.")
        model.typeInURLBar("hh")
        #expect(model.message == .error("No URL in this curl command."))
    }

    @Test func `a send clears an error`() {
        model.message = .error("No URL in this curl command.")
        model.send()
        #expect(model.message == nil)
    }

    @Test(arguments: [("post", "POST"), (" propfind ", "PROPFIND"), ("", "GET"), ("  ", "GET")])
    func `a method is stored uppercased, and a blank one keeps the old`(typed: String, stored: String) {
        model.setMethod(typed)
        #expect(model.tab.definition.method == stored)
    }

    // MARK: Path Variables

    @Test func `typing :i then d leaves no value for i, and a value for id survives a host edit`() {
        model.typeInURLBar("http://h/:i")
        model.setPathVariable("i", to: "1")
        model.typeInURLBar("http://h/:id")
        #expect(model.tab.definition.pathVariables == [:])

        model.setPathVariable("id", to: "7")
        model.typeInURLBar("http://other/:id")
        #expect(model.tab.definition.pathVariables == ["id": "7"])
        model.typeInURLBar("http://other/x")
        #expect(model.tab.definition.pathVariables == [:])
    }

    @Test func `a value is set for a name the URL has, and an empty one removes it`() {
        model.typeInURLBar("http://h/:id")
        model.setPathVariable("id", to: "7")
        #expect(model.tab.definition.pathVariables == ["id": "7"])
        model.setPathVariable("nope", to: "x")
        #expect(model.tab.definition.pathVariables == ["id": "7"])
        model.setPathVariable("id", to: "")
        #expect(model.tab.definition.pathVariables == [:])
    }

    @Test func `setting a value makes a Request Dirty and clearing it makes it clean again`() {
        model.typeInURLBar("http://h/:id")
        model.tab.source = .request(RequestID(UUID()))
        model.tab.baseline = model.tab.definition
        #expect(!model.tab.isDirty)
        model.setPathVariable("id", to: "7")
        #expect(model.tab.isDirty)
        model.setPathVariable("id", to: "")
        #expect(!model.tab.isDirty)
    }

    @Test func `a curl command pasted into a Tab leaves pathVariables empty`() {
        model.typeInURLBar("http://h/:id")
        model.setPathVariable("id", to: "7")
        #expect(model.pasteInURLBar("curl http://x/:id"))
        #expect(model.tab.definition.url == "http://x/:id")
        #expect(model.tab.definition.pathVariables == [:])
    }
}

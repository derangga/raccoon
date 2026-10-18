@testable import Raccoon
import RaccoonDomain
import RaccoonTesting
import Testing

@MainActor
struct TabModelEditingTests {
    let model = TabModel(transport: ScriptedTransport(.failure(.timedOut)), secrets: InMemorySecretStore(), files: DictionaryFileReading([:]), instants: FixedInstantSource(.now))

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
}

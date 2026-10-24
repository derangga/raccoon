import AppKit
@testable import Raccoon
import RaccoonDomain
import RaccoonTesting
import Testing

/// Send and Copy as Curl against the window's Variables, with secrets from an in-memory store.
@MainActor
struct VariableSendTests {
    let response = Response(status: 200, headers: [], body: Data(), elapsed: .zero, byteCount: 0)
    let transport: ScriptedTransport
    let secrets = InMemorySecretStore()
    let clipboard = RecordingClipboardWriter()
    let model: TabModel
    let token = VariableName("token")!

    static let staging = Environment(name: "Staging", entries: [
        VariableEntry(name: VariableName("host")!, value: .plain("staging.example")),
        VariableEntry(name: VariableName("token")!, value: .secret),
    ])

    init() {
        transport = ScriptedTransport(.success(response))
        model = TabModel(transport: transport, secrets: secrets, files: DictionaryFileReading([:]), instants: FixedInstantSource(.now),
                         clipboard: clipboard)
        model.variables = { (Self.staging, Globals(entries: [])) }
        model.tab.definition.url = "https://{{host}}/charges"
        model.tab.definition.auth = .bearer(token: "{{token}}")
    }

    @Test func `an Undefined Variable sends nothing, never shows sending, and the message names every one`() {
        model.tab.definition.url = "https://{{host}}/charges/{{charge_id}}"
        model.tab.definition.headers = [Row(name: "X-Tenant", value: "{{tenant_id}}")]
        try? secrets.set("s3cret", environment: "Staging", name: token)

        model.send()

        #expect(transport.requests.isEmpty)
        #expect(model.tab.response == .idle)
        #expect(model.inFlight == nil)
        #expect(model.message == .error("Not sent. charge_id and tenant_id are not defined in Staging or in Globals."))
    }

    @Test func `a blocked send keeps the last Response on screen`() async throws {
        try secrets.set("s3cret", environment: "Staging", name: token)
        model.send()
        await model.inFlight?.value
        model.tab.definition.url = "https://{{nope}}/"

        model.send()

        #expect(model.tab.response == .received(response))
        #expect(transport.requests.count == 1)
    }

    @Test func `a secret is read from the store at send, and one the store lacks is undefined`() async throws {
        model.send()
        #expect(transport.requests.isEmpty)
        #expect(model.message == .error("Not sent. token is not defined in Staging or in Globals."))

        try secrets.set("s3cret", environment: "Staging", name: token)
        model.send()
        await model.inFlight?.value

        #expect(model.message == nil)
        #expect(transport.requests.map { $0.definition.headers } == [[Row(name: "Authorization", value: "Bearer s3cret")]])
    }

    @Test func `no model property holds a secret value after a send or a copy`() async throws {
        try secrets.set("s3cret", environment: "Staging", name: token)
        model.send()
        await model.inFlight?.value
        model.copyAsCurl(includeSecrets: true)

        var dumped = ""
        dump(model, to: &dumped)
        #expect(!dumped.contains("s3cret"))
        #expect(clipboard.string?.contains("s3cret") == true)
    }

    @Test func `Copy as Curl leaves a secret as {{token}} unless secrets are included`() throws {
        try secrets.set("s3cret", environment: "Staging", name: token)

        model.copyAsCurl()
        #expect(clipboard.string == "curl 'https://staging.example/charges' \\\n  -H 'Authorization: Bearer {{token}}'")

        model.copyAsCurl(includeSecrets: true)
        #expect(clipboard.string == "curl 'https://staging.example/charges' \\\n  -H 'Authorization: Bearer s3cret'")
    }

    @Test func `an Undefined Variable disables Copy as Curl, copies nothing, and the item names it`() throws {
        model.tab.definition.url = "https://{{nope}}/charges"
        let controller = TabViewController(model: model, theme: ThemeEnvironment(catalog: ThemeCatalog.load(), isDark: false))
        let item = MainMenu.copyAsCurl()

        #expect(!controller.validateMenuItem(item))
        #expect(item.title == "Copy as Curl (nope is not defined)")
        controller.copyAsCurl(item)
        #expect(clipboard.string == nil)

        model.tab.definition.url = "https://{{host}}/charges"
        #expect(controller.validateMenuItem(item))
        #expect(item.title == "Copy as Curl")
    }
}

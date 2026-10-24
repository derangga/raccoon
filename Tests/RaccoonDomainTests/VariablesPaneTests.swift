import RaccoonDomain
import Testing

/// The inspector's Variables pane: what the selected Tab resolves against, grouped.
struct VariablesPaneTests {
    func entry(_ name: String, _ value: VariableEntry.Value, enabled: Bool = true) -> VariableEntry {
        VariableEntry(name: VariableName(name)!, isEnabled: enabled, value: value)
    }

    func name(_ raw: String) -> VariableName { VariableName(raw)! }

    func definition(url: String = "", headers: [Row] = [], body: Body = .none, auth: Auth = .none) -> RequestDefinition {
        var definition = RequestDefinition.empty
        definition.url = url
        definition.headers = headers
        definition.body = body
        definition.auth = auth
        return definition
    }

    @Test func `board 04: missing names first with where the Tab uses them, then Staging, then Globals struck where overridden`() {
        let staging = Environment(name: "Staging", entries: [
            entry("region", .plain("eu-central-1")), entry("api_key", .secret), entry("host", .plain("https://api.staging")),
        ])
        let globals = Globals(entries: [entry("host", .plain("http://localhost:4000")), entry("user_agent", .plain("Raccoon/1.0"))])
        let tab = definition(
            url: "{{host}}/v1/charges/{{charge_id}}",
            headers: [Row(name: "X-Tenant", value: "{{tenant_id}}"), Row(name: "Old", value: "{{gone}}", isEnabled: false)]
        )

        let pane = VariablesPane(definition: tab, active: staging, globals: globals)

        #expect(pane.undefined == [
            .init(name: name("charge_id"), shown: .usedIn(["URL"])),
            .init(name: name("tenant_id"), shown: .usedIn(["Headers"])),
        ])
        #expect(pane.environment == "Staging")
        // The names this Tab uses first, then the rest, each in file order.
        #expect(pane.active == [
            .init(name: name("host"), shown: .value("https://api.staging"), index: 2),
            .init(name: name("region"), shown: .value("eu-central-1"), index: 0),
            .init(name: name("api_key"), shown: .secret, index: 1),
        ])
        #expect(pane.globals == [
            .init(name: name("host"), shown: .value("http://localhost:4000"), isOverridden: true, index: 0),
            .init(name: name("user_agent"), shown: .value("Raccoon/1.0"), index: 1),
        ])
    }

    @Test func `a name used in several places lists each place once, in editor order`() {
        let tab = definition(
            url: "{{a}}", headers: [Row(name: "{{a}}", value: "{{a}}")],
            body: .multipart([Part(name: "f", content: .file(path: "{{a}}/x"))]), auth: .bearer(token: "{{a}}")
        )
        let pane = VariablesPane(definition: tab, active: nil, globals: Globals(entries: []))
        #expect(pane.undefined == [.init(name: name("a"), shown: .usedIn(["URL", "Headers", "Body", "Auth"]))])
    }

    @Test func `No Environment: Globals only, nothing overridden; disabled Variables are not listed`() {
        let globals = Globals(entries: [entry("host", .plain("h")), entry("off", .plain("x"), enabled: false)])
        let pane = VariablesPane(definition: definition(url: "{{off}}"), active: nil, globals: globals)
        #expect(pane.environment == nil && pane.active.isEmpty)
        #expect(pane.globals == [.init(name: name("host"), shown: .value("h"), index: 0)])
        #expect(pane.undefined == [.init(name: name("off"), shown: .usedIn(["URL"]))])
    }

    @Test func `each row knows its place in its file, Disabled Rows counted`() {
        let globals = Globals(entries: [entry("off", .plain("x"), enabled: false), entry("host", .plain("h"))])
        #expect(VariablesPane(definition: .empty, active: nil, globals: globals).globals.map(\.index) == [1])
    }

    @Test func `a disabled Environment entry overrides nothing`() {
        let staging = Environment(name: "Staging", entries: [entry("host", .plain("s"), enabled: false)])
        let pane = VariablesPane(definition: .empty, active: staging, globals: Globals(entries: [entry("host", .plain("g"))]))
        #expect(pane.active.isEmpty)
        #expect(pane.globals == [.init(name: name("host"), shown: .value("g"), index: 0)])
    }

    @Test(arguments: [
        ("charge_id", VariablesPane.Group.undefined, 0),
        ("host", .active, 0),
        ("user_agent", .globals, 1),
    ])
    func `the selected name is the row that resolves, never a struck-out Global`(raw: String, group: VariablesPane.Group, index: Int) {
        let pane = VariablesPane(
            definition: definition(url: "{{host}}/{{charge_id}}"),
            active: Environment(name: "Staging", entries: [entry("host", .plain("s"))]),
            globals: Globals(entries: [entry("host", .plain("g")), entry("user_agent", .plain("u"))])
        )
        #expect(pane.row(of: name(raw))! == VariablesPane.Place(group: group, index: index))
        #expect(pane.row(of: name("nowhere")) == nil)
    }
}

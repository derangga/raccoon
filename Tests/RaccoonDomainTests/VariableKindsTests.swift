import Foundation
import RaccoonDomain
import Testing

struct VariableKindsTests {
    func entry(_ name: String, _ value: VariableEntry.Value, enabled: Bool = true) -> VariableEntry {
        VariableEntry(name: VariableName(name)!, isEnabled: enabled, value: value)
    }

    @Test func `each token is coloured as defined, secret or undefined, with no value read`() {
        let globals = Globals(entries: [entry("host", .plain("g")), entry("key", .secret), entry("off", .plain("x"), enabled: false)])
        let staging = Environment(name: "Staging", entries: [entry("key", .plain("visible")), entry("token", .secret)])
        let kinds = VariableKinds(active: staging, globals: globals)

        let ranges = kinds.ranges(in: "{{host}}/{{token}}?{{key}}&{{off}}")

        #expect(ranges == [
            HighlightRange(range: NSRange(location: 0, length: 8), token: .variableDefined),
            HighlightRange(range: NSRange(location: 9, length: 9), token: .variableSecret),
            HighlightRange(range: NSRange(location: 19, length: 7), token: .variableDefined),
            HighlightRange(range: NSRange(location: 27, length: 7), token: .variableUndefined),
        ])
    }

    @Test func `with no Active Environment only Globals count`() {
        let kinds = VariableKinds(active: nil, globals: Globals(entries: [entry("key", .secret)]))
        #expect(kinds.ranges(in: "{{key}}{{token}}").map(\.token) == [.variableSecret, .variableUndefined])
        #expect(kinds.holdsUndefined("{{key}}{{token}}"))
        #expect(!kinds.holdsUndefined("{{key}} plain"))
    }
}

struct VariableTooltipTests {
    func entry(_ name: String, _ value: VariableEntry.Value, enabled: Bool = true) -> VariableEntry {
        VariableEntry(name: VariableName(name)!, isEnabled: enabled, value: value)
    }

    let globals = Globals(entries: [
        VariableEntry(name: VariableName("host")!, value: .plain("g.example.com")),
        VariableEntry(name: VariableName("key")!, value: .secret),
        VariableEntry(name: VariableName("off")!, isEnabled: false, value: .plain("x")),
    ])
    var staging: Environment {
        Environment(name: "Staging", entries: [
            VariableEntry(name: VariableName("host")!, value: .plain("s.example.com")),
            VariableEntry(name: VariableName("token")!, value: .secret),
        ])
    }

    @Test func `a defined name says where its value comes from, the Environment's over a Global's`() {
        let kinds = VariableKinds(active: staging, globals: globals)

        #expect(kinds.tooltip(for: VariableName("host")!) == .defined(VariableName("host")!, source: "Staging", value: "s.example.com"))
        #expect(VariableKinds(active: nil, globals: globals).tooltip(for: VariableName("host")!)
            == .defined(VariableName("host")!, source: "Globals", value: "g.example.com"))
    }

    @Test func `a secret says Secret and its source, and carries no value`() {
        let kinds = VariableKinds(active: staging, globals: globals)

        #expect(kinds.tooltip(for: VariableName("token")!) == .secret(VariableName("token")!, source: "Staging"))
        #expect(kinds.tooltip(for: VariableName("key")!) == .secret(VariableName("key")!, source: "Globals"))
        #expect(kinds.tooltip(for: VariableName("key")!).detail == "Secret")
    }

    @Test func `an undefined name, or a disabled one, says where it was looked for`() {
        let withEnvironment = VariableKinds(active: staging, globals: globals)
        let globalsOnly = VariableKinds(active: nil, globals: globals)

        #expect(withEnvironment.tooltip(for: VariableName("off")!) == .undefined(VariableName("off")!, environment: "Staging"))
        #expect(withEnvironment.tooltip(for: VariableName("charge_id")!).detail == "Not defined in Staging or Globals")
        #expect(globalsOnly.tooltip(for: VariableName("charge_id")!).detail == "Not defined in Globals")
    }

    @Test func `each kind has a heading and a detail`() {
        let kinds = VariableKinds(active: staging, globals: globals)

        let defined = kinds.tooltip(for: VariableName("host")!)
        #expect(defined.name.rawValue == "host" && defined.source == "Staging" && defined.detail == "s.example.com")
        #expect(kinds.tooltip(for: VariableName("zzz")!).source == nil)
    }
}

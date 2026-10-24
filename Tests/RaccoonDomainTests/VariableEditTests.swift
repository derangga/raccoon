import RaccoonDomain
import Testing

struct VariableEditTests {
    let entries = [
        VariableEntry(name: VariableName("host")!, value: .plain("a")),
        VariableEntry(name: VariableName("tenant")!, value: .plain("b")),
    ]

    @Test(arguments: [
        ("token", nil, "token"),
        ("  token  ", nil, "token"),
        ("api.v2_key-1", nil, "api.v2_key-1"),
        ("host", 0, "host"),
    ] as [(String, Int?, String)])
    func `a valid name is accepted, trimmed, and a row may keep its own`(text: String, replacing: Int?, name: String) throws {
        #expect(try VariableEdit.name(text, in: entries, replacing: replacing).rawValue == name)
    }

    @Test(arguments: [
        ("", nil, VariableEdit.Refusal.invalidName),
        ("a b", 0, .invalidName),
        ("é", 1, .invalidName),
        ("{{x}}", nil, .invalidName),
        ("tenant", nil, .duplicate(VariableName("tenant")!)),
        ("tenant", 0, .duplicate(VariableName("tenant")!)),
    ] as [(String, Int?, VariableEdit.Refusal)])
    func `an invalid or repeated name is refused`(text: String, replacing: Int?, refusal: VariableEdit.Refusal) {
        #expect(throws: refusal) { try VariableEdit.name(text, in: entries, replacing: replacing) }
    }

    @Test(arguments: [
        (VariableEdit.Refusal.invalidName, "Staging", "Names use letters, digits, _, - and . only."),
        (.duplicate(VariableName("tenant")!), "Staging", "tenant is already in Staging."),
        (.duplicate(VariableName("tenant")!), nil, "tenant is already in Globals."),
    ] as [(VariableEdit.Refusal, String?, String)])
    func `a refusal reads as the line under the row`(refusal: VariableEdit.Refusal, set: String?, line: String) {
        #expect(refusal.message(in: set) == line)
    }

    @Test(arguments: [
        ("Prod", ["Dev", "Prod"], nil, "Prod"),
        ("prod", ["Dev", "Prod"], nil, "Prod"),
        ("Prod", ["Dev", "Prod"], "Prod", nil),
        ("PROD", ["Dev", "Prod"], "Prod", nil),
        ("Staging", ["Dev", "Prod"], nil, nil),
    ] as [(String, [String], String?, String?)])
    func `an Environment name clashes with another one regardless of case`(proposed: String, names: [String], own: String?, clash: String?) {
        #expect(EnvironmentName.clash(proposed, among: names, except: own) == clash)
    }
}

import Foundation
import RaccoonDomain
import Testing

struct EnvironmentFileTests {
    func name(_ text: String) -> VariableName { VariableName(text)! }

    @Test func `plain, disabled and secret entries come back as they went in`() throws {
        let entries = [
            VariableEntry(name: name("host"), value: .plain("https://api.example.com")),
            VariableEntry(name: name("old"), isEnabled: false, value: .plain("x")),
            VariableEntry(name: name("token"), value: .secret),
        ]

        let decoded = try EnvironmentFile.decode(EnvironmentFile.encode(entries), path: "environments/Dev.json")

        #expect(decoded.entries == entries)
        #expect(decoded.droppedSecretValues.isEmpty)
    }

    @Test func `a secret is written with no value`() {
        let text = String(decoding: EnvironmentFile.encode([VariableEntry(name: name("token"), value: .secret)]), as: UTF8.self)

        #expect(text == """
            {
              "variables" : [
                {
                  "isEnabled" : true,
                  "name" : "token",
                  "secret" : true
                }
              ],
              "version" : 1
            }

            """)
    }

    @Test func `a secret someone gave a value decodes without it and names it`() throws {
        let json = #"{"version": 1, "variables": [{"name": "token", "secret": true, "value": "sk_live_1"}]}"#

        let decoded = try EnvironmentFile.decode(Data(json.utf8), path: "globals.json")

        #expect(decoded.entries == [VariableEntry(name: name("token"), value: .secret)])
        #expect(decoded.droppedSecretValues == [name("token")])
    }

    @Test func `isEnabled absent means enabled, and no variables is none`() throws {
        #expect(try EnvironmentFile.decode(Data(#"{"version": 1, "variables": [{"name": "a", "value": "1"}]}"#.utf8), path: "globals.json").entries
            == [VariableEntry(name: name("a"), value: .plain("1"))])
        #expect(try EnvironmentFile.decode(Data(#"{"version": 1}"#.utf8), path: "globals.json").entries.isEmpty)
    }

    @Test(arguments: [
        #"{"version": 2, "variables": []}"#,
        #"{"variables": []}"#,
        #"{"version": 1, "variables": [{"name": "a b", "value": "1"}]}"#,
        #"{"version": 1, "variables": [{"name": "a"}]}"#,
        "not json",
    ])
    func `an unknown version, a bad name, an entry with neither value nor secret, or not JSON is undecodable`(json: String) {
        #expect {
            try EnvironmentFile.decode(Data(json.utf8), path: "environments/Dev.json")
        } throws: { error in
            if case .undecodable(path: "environments/Dev.json", _) = error as? StoreError { true } else { false }
        }
    }

    @Test(arguments: [
        ("not json", "Not valid JSON at line 1"),
        ("{\n  \"version\": 1,\n  oops", "Not valid JSON at line 3"),
        (#"{"version": 2, "variables": []}"#, "Unknown file version 2"),
        (#"{"variables": []}"#, "Missing “version”"),
        (#"{"version": 1, "variables": [{"name": "a b", "value": "1"}]}"#, "“a b” is not a Variable name"),
    ])
    func `an undecodable file says why in a sentence the sheet can show`(json: String, reason: String) {
        #expect {
            try EnvironmentFile.decode(Data(json.utf8), path: "environments/Dev.json")
        } throws: { error in
            error as? StoreError == .undecodable(path: "environments/Dev.json", reason: reason)
        }
    }
}

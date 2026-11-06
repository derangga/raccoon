import Foundation
@testable import Raccoon
import RaccoonDomain
import Testing

/// What the Environment Export sheet says (design-system §6): each string, from an Environment.
@MainActor
struct EnvironmentExportModelTests {
    func environment(_ name: String = "Staging", plain: Int = 0, secrets: Int = 0) -> Environment {
        Environment(name: name, entries:
            (0..<plain).map { VariableEntry(name: VariableName("p\($0)")!, value: .plain("v")) }
            + (0..<secrets).map { VariableEntry(name: VariableName("s\($0)")!, value: .secret) })
    }

    @Test func `the title names the Environment, and the file is named for it`() {
        let model = EnvironmentExportModel(environment("Staging"))
        #expect(model.title == "Export “Staging”")
        #expect(model.fileName == "Staging.postman_environment.json")
    }

    @Test func `a name with / or : is a file name as Requests are, and the title keeps it`() {
        let model = EnvironmentExportModel(environment("EU/West: 2"))
        #expect(model.title == "Export “EU/West: 2”")
        #expect(model.fileName == "EU-West- 2.postman_environment.json")
    }

    @Test(arguments: [
        (12, 2, "14 Variables, 2 secrets"), (0, 1, "1 Variable, 1 secret"), (0, 0, "0 Variables, 0 secrets"),
        (1_198, 2, "1,200 Variables, 2 secrets"),
    ])
    func `the counts: every entry is a Variable, and the secrets are among them`(plain: Int, secrets: Int, text: String) {
        #expect(EnvironmentExportModel(environment(plain: plain, secrets: secrets)).counts == text)
    }

    @Test func `the checkbox is drawn only when there is a secret`() {
        #expect(EnvironmentExportModel(environment(plain: 3)).hasSecrets == false)
        #expect(EnvironmentExportModel(environment(plain: 3, secrets: 1)).hasSecrets)
    }

    @Test func `the hint says what each state writes`() {
        let model = EnvironmentExportModel(environment(secrets: 1))
        #expect(model.hint(ticked: false) == "Secrets are exported empty.")
        #expect(model.hint(ticked: true) == "Secret values are written to the file in plain text.")
    }

    @Test func `the result says where the file went, and how many secrets are empty in it`() {
        let model = EnvironmentExportModel(environment(secrets: 3))
        #expect(model.exported("Staging.postman_environment.json") == "Exported to Staging.postman_environment.json")
        #expect(model.unreadable(2) == "2 secrets could not be read from the Keychain and are empty in the file.")
        #expect(model.unreadable(1) == "1 secret could not be read from the Keychain and is empty in the file.")
    }

    @Test func `a failed write is the red line, with the reason as a sentence`() {
        let model = EnvironmentExportModel(environment())
        #expect(model.failure(.unwritable(path: "/x", reason: "the folder “Archive” is not writable")) == "Not exported. The folder “Archive” is not writable.")
        #expect(model.failure(.unwritable(path: "/x", reason: "Permission denied.")) == "Not exported. Permission denied.")
    }
}

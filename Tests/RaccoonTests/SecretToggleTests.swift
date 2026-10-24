import Foundation
@testable import Raccoon
import RaccoonData
import RaccoonDomain
import RaccoonTesting
import Testing

/// Marking, unmarking and filling in Secret Variables through the window, over a temp Data Folder
/// and a Keychain that can refuse.
@MainActor
struct SecretToggleTests {
    let temp = FileManager.default.temporaryDirectory.appending(path: "raccoon-\(UUID())")
    var root: URL { temp.appending(path: "Raccoon") }
    let secrets = FlakySecretStore()
    let token = VariableName("token")!
    let refused = SecretError.unavailable(-25308)

    func makeWindow() -> WindowModel {
        let window = WindowModel(
            dataFolder: .test(root), folderWatch: ManualFolderWatch(),
            sessionStore: DiskSessionStore(directory: temp.appending(path: "Support"), root: root.path),
            secrets: secrets, instants: FixedInstantSource(.now),
            makeTab: { [secrets] in
                TabModel(transport: ScriptedTransport(.failure(.timedOut)), secrets: secrets, files: DictionaryFileReading([:]),
                         instants: FixedInstantSource(.now), clipboard: RecordingClipboardWriter())
            }
        )
        window.loadDataFolder()
        return window
    }

    func put(_ entries: [VariableEntry], at path: String) throws {
        let url = root.appending(path: path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try EnvironmentFile.encode(entries).write(to: url)
    }

    func plain(_ name: String, _ value: String) -> VariableEntry { VariableEntry(name: VariableName(name)!, value: .plain(value)) }
    var secret: VariableEntry { VariableEntry(name: token, value: .secret) }
    func bytes(_ path: String) throws -> Data { try Data(contentsOf: root.appending(path: path)) }

    /// Staging holds `host` and a plain `token`.
    func withPlainToken() throws -> WindowModel {
        try put([plain("host", "a"), plain("token", "sk_live")], at: "environments/Staging.json")
        return makeWindow()
    }

    // MARK: Mark

    @Test func `marking stores the value in the Keychain, then rewrites the file without it`() throws {
        let window = try withPlainToken()
        window.pickActiveEnvironment("Staging")

        try window.markSecret(at: 1, in: "Staging")

        #expect(try secrets.get(environment: "Staging", name: token) == "sk_live")
        #expect(try bytes("environments/Staging.json") == EnvironmentFile.encode([plain("host", "a"), secret]))
        #expect(!String(decoding: try bytes("environments/Staging.json"), as: UTF8.self).contains("sk_live"))
        #expect(window.entries(of: "Staging") == [plain("host", "a"), secret])
        #expect(window.tabs[0].scope(.read).values[token] == "sk_live")
    }

    @Test func `a Keychain write that fails leaves the file bytes and the row as they were`() throws {
        let window = try withPlainToken()
        let before = try bytes("environments/Staging.json")
        secrets.refuse(.set, with: refused)

        #expect(throws: SecretEditError.secret(refused)) { try window.markSecret(at: 1, in: "Staging") }

        #expect(try bytes("environments/Staging.json") == before)
        #expect(window.entries(of: "Staging") == [plain("host", "a"), plain("token", "sk_live")])
        #expect(try secrets.inner.get(environment: "Staging", name: token) == nil)
    }

    @Test func `a file write that fails after the Keychain took the value removes the item again`() throws {
        let window = try withPlainToken()
        let folder = root.appending(path: "environments")
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: folder.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: folder.path) }
        let before = try bytes("environments/Staging.json")

        #expect(throws: SecretEditError.self) { try window.markSecret(at: 1, in: "Staging") }

        #expect(try bytes("environments/Staging.json") == before)
        #expect(try secrets.inner.get(environment: "Staging", name: token) == nil)
    }

    @Test func `marking a row with an empty value sends nothing to the Keychain and is missing until one is typed`() throws {
        try put([plain("token", "")], at: "environments/Staging.json")
        let window = makeWindow()

        try window.markSecret(at: 0, in: "Staging")

        #expect(try secrets.inner.get(environment: "Staging", name: token) == nil)
        #expect(window.entries(of: "Staging") == [secret])
        #expect(window.missingSecrets(in: "Staging") == [token])

        try window.setSecretValue("sk_new", at: 0, in: "Staging")
        #expect(window.missingSecrets(in: "Staging").isEmpty)
    }

    @Test func `marking an empty value leaves no stale Keychain item to be sent, and a delete that fails changes nothing`() throws {
        try put([plain("token", "")], at: "environments/Staging.json")
        try secrets.set("stale", environment: "Staging", name: token)
        let window = makeWindow()
        window.pickActiveEnvironment("Staging")
        let before = try bytes("environments/Staging.json")
        secrets.refuse(.delete, with: refused)

        #expect(throws: SecretEditError.secret(refused)) { try window.markSecret(at: 0, in: "Staging") }
        #expect(try bytes("environments/Staging.json") == before)

        secrets.refuse(.delete, with: nil)
        try window.markSecret(at: 0, in: "Staging")

        #expect(try secrets.inner.get(environment: "Staging", name: token) == nil)
        #expect(window.tabs[0].scope(.read).values[token] == nil)
    }

    // MARK: Unmark

    @Test func `unmarking rewrites the file with the value, then deletes the Keychain item`() throws {
        try put([secret], at: "environments/Staging.json")
        try secrets.set("sk_live", environment: "Staging", name: token)
        let window = makeWindow()

        try window.unmarkSecret(at: 0, in: "Staging")

        #expect(try bytes("environments/Staging.json") == EnvironmentFile.encode([plain("token", "sk_live")]))
        #expect(try secrets.inner.get(environment: "Staging", name: token) == nil)
    }

    @Test func `an item that cannot be deleted after unmarking is logged, not an error: the file already has the value`() throws {
        try put([secret], at: "environments/Staging.json")
        try secrets.set("sk_live", environment: "Staging", name: token)
        secrets.refuse(.delete, with: refused)
        let window = makeWindow()

        try window.unmarkSecret(at: 0, in: "Staging")

        #expect(window.entries(of: "Staging") == [plain("token", "sk_live")])
    }

    @Test(arguments: [SecretError?.none, .some(.unavailable(-25308))])
    func `unmarking a secret the Keychain cannot give writes an empty value and deletes nothing`(failure: SecretError?) throws {
        try put([secret], at: "environments/Staging.json")
        try secrets.set("hidden", environment: "Staging", name: token)
        if let failure { secrets.refuse(.get, with: failure) } else { try secrets.inner.delete(environment: "Staging", name: token) }
        let window = makeWindow()

        try window.unmarkSecret(at: 0, in: "Staging")

        #expect(window.entries(of: "Staging") == [plain("token", "")])
        #expect(try secrets.inner.get(environment: "Staging", name: token) == (failure == nil ? nil : "hidden"))
    }

    // MARK: Typing a secret's value

    @Test func `typing a secret's value stores it and never touches the file`() throws {
        try put([secret], at: "environments/Staging.json")
        let window = makeWindow()
        let before = try bytes("environments/Staging.json")

        try window.setSecretValue("sk_new", at: 0, in: "Staging")

        #expect(try secrets.get(environment: "Staging", name: token) == "sk_new")
        #expect(try bytes("environments/Staging.json") == before)
    }

    @Test(arguments: [SecretError.unavailable(-25308), .raccoonJSONUnreadable])
    func `a value the Keychain refuses is thrown and stored nowhere`(failure: SecretError) throws {
        try put([secret], at: "environments/Staging.json")
        secrets.refuse(.set, with: failure)
        let window = makeWindow()

        #expect(throws: failure) { try window.setSecretValue("sk_new", at: 0, in: "Staging") }
        #expect(try secrets.inner.get(environment: "Staging", name: token) == nil)
    }

    // MARK: Missing

    @Test func `the sheet's check reads each secret once, and a secret the Keychain cannot give is missing and undefined`() throws {
        let other = VariableName("api_key")!
        try put([secret, VariableEntry(name: other, value: .secret), plain("host", "a")], at: "environments/Staging.json")
        try secrets.set("sk", environment: "Staging", name: token)
        let window = makeWindow()
        window.pickActiveEnvironment("Staging")
        let before = secrets.gets

        #expect(window.missingSecrets(in: "Staging") == [other])
        #expect(secrets.gets - before == 2)

        secrets.refuse(.get, with: refused)
        #expect(window.missingSecrets(in: "Staging") == [token, other])
        #expect(window.tabs[0].scope(.read).values[token] == nil)
    }

    // MARK: No secret value in the Data Folder

    @Test func `no secret value is in any file under the temp root after marking, editing and renaming`() throws {
        let window = try withPlainToken()
        try window.markSecret(at: 1, in: "Staging")
        try window.setSecretValue("sk_typed_9f3", at: 1, in: "Staging")
        try window.renameEnvironment("Staging", to: "Production")
        window.pickActiveEnvironment("Production")
        #expect(window.tabs[0].scope(.read).values[token] == "sk_typed_9f3")

        let files = try #require(FileManager.default.enumerator(at: temp, includingPropertiesForKeys: [.isRegularFileKey]))
        var read = 0
        for case let url as URL in files where (try url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile ?? false) {
            let text = String(decoding: try Data(contentsOf: url), as: UTF8.self)
            #expect(!text.contains("sk_live") && !text.contains("sk_typed_9f3"), "\(url.lastPathComponent)")
            read += 1
        }
        #expect(read >= 1)
    }
}

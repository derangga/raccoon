import Foundation
@testable import Raccoon
import RaccoonData
import RaccoonDomain
import RaccoonTesting
import Testing

/// Include secret values: what the window asks the SecretStore for, and what it does with the answers.
@MainActor
struct ReadSecretsTests {
    let temp = FileManager.default.temporaryDirectory.appending(path: "raccoon-\(UUID())")
    let store = FlakySecretStore()
    let token = VariableName("token")!
    let key = VariableName("key")!
    let pin = VariableName("pin")!

    func makeWindow() -> WindowModel {
        let root = temp.appending(path: "Raccoon")
        return WindowModel(
            dataFolder: .test(root), folderWatch: ManualFolderWatch(),
            sessionStore: DiskSessionStore(directory: temp.appending(path: "Support"), root: root.path),
            secrets: store, instants: FixedInstantSource(.now),
            makeTab: { [store] in
                TabModel(transport: ScriptedTransport(.failure(.timedOut(seconds: 60))), secrets: store, files: DictionaryFileReading([:]),
                         instants: FixedInstantSource(.now), clipboard: RecordingClipboardWriter())
            }
        )
    }

    func staging() -> Environment {
        Environment(name: "Staging", entries: [
            VariableEntry(name: VariableName("host")!, value: .plain("api.example.com")),
            VariableEntry(name: token, value: .secret),
            VariableEntry(name: key, isEnabled: false, value: .secret),
            VariableEntry(name: pin, value: .secret),
        ])
    }

    @Test func `every Secret Variable is read once from its Environment, enabled or not, and a Plain one never`() throws {
        try store.inner.set("t-1", environment: "Staging", name: token)
        try store.inner.set("k-1", environment: "Staging", name: key)
        try store.inner.set("p-1", environment: "Staging", name: pin)

        let secrets = makeWindow().readSecrets(of: staging())

        #expect(secrets == EnvironmentSecrets(values: [token: "t-1", key: "k-1", pin: "p-1"], unreadable: []))
        #expect(store.inner.gets == [token, key, pin].map { .init(environment: "Staging", name: $0) })
    }

    @Test func `a secret with no Keychain item is empty and not named`() throws {
        try store.inner.set("t-1", environment: "Staging", name: token)

        let secrets = makeWindow().readSecrets(of: staging())

        #expect(secrets.values == [token: "t-1"])
        #expect(secrets.unreadable.isEmpty)
    }

    @Test func `a refused read names that one secret and the others are still read`() throws {
        try store.inner.set("t-1", environment: "Staging", name: token)
        try store.inner.set("p-1", environment: "Staging", name: pin)
        store.refuseGets(of: [key], with: .unavailable(-128))

        let secrets = makeWindow().readSecrets(of: staging())

        #expect(secrets == EnvironmentSecrets(values: [token: "t-1", pin: "p-1"], unreadable: [key]))
    }
}

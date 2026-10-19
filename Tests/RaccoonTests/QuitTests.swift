import Foundation
@testable import Raccoon
import OSLog
import RaccoonData
import RaccoonDomain
import RaccoonTesting
import Testing

@MainActor
struct QuitTests {
    let directory = FileManager.default.temporaryDirectory.appending(path: "raccoon-\(UUID())")

    func makeWindow(store: any SessionStore, transport: ScriptedTransport = ScriptedTransport(.failure(.timedOut))) -> WindowModel {
        WindowModel(
            dataFolder: DiskDataFolderStore(root: directory.appending(path: "Raccoon")), folderWatch: ManualFolderWatch(),
            sessionStore: store, secrets: InMemorySecretStore(), instants: FixedInstantSource(.now),
            makeTab: {
                TabModel(transport: transport, secrets: InMemorySecretStore(), files: DictionaryFileReading([:]),
                         instants: FixedInstantSource(.now), clipboard: RecordingClipboardWriter())
            }
        )
    }

    @Test func `quit with a Dirty Tab and a Draft keeps both in session.json`() throws {
        let store = DiskSessionStore(directory: directory)
        let window = makeWindow(store: store)
        window.newTab()
        let (dirty, draft) = (window.tabs[0], window.tabs[1])
        dirty.tab.source = .request(RequestID(UUID()))
        dirty.tab.baseline = dirty.tab.definition
        dirty.typeInURLBar("https://api.example.com/charges")
        draft.typeInURLBar("https://api.example.com/v1/webhooks")

        window.quit()

        let session = try SessionFile.decode(try #require(try store.read()))
        #expect(session.tabs == [dirty.tab.snapshot, draft.tab.snapshot])
        #expect(session.tabs[0].definition != session.tabs[0].baseline)
        #expect(session.selected == draft.tab.id)
    }

    /// Records, at the moment of the write, whether each Tab's send was still running.
    final class OrderingStore: SessionStore, @unchecked Sendable {
        var sendsRunningAtWrite: [Bool]?
        var tabs: () -> [TabModel] = { [] }
        func read() throws(StoreError) -> Data? { nil }
        func write(_ data: Data) throws(StoreError) {
            if sendsRunningAtWrite == nil {
                sendsRunningAtWrite = MainActor.assumeIsolated { tabs().map { $0.inFlight != nil } }
            }
        }
        func setAside() throws(StoreError) -> String { "" }
    }

    @Test func `the Session is written before any Tab is released`() async throws {
        let store = OrderingStore()
        let window = makeWindow(store: store)
        store.tabs = { window.tabs }
        window.tabs[0].typeInURLBar("http://localhost/slow")
        // Changes schedule their writes on a later Task, so quit's is the first.
        window.tabs[0].send()
        let task = try #require(window.tabs[0].inFlight)

        window.quit()

        #expect(store.sendsRunningAtWrite == [true])
        #expect(window.tabs[0].inFlight == nil)
        await task.value
        #expect(window.tabs[0].tab.response == .idle)
    }

    @Test func `an unwritable Session on quit is logged, and quit goes on`() async throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: directory.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path) }
        let since = Date.now
        let window = makeWindow(store: DiskSessionStore(directory: directory))
        window.tabs[0].typeInURLBar("http://localhost/slow")
        window.tabs[0].send()

        window.quit()

        #expect(window.tabs[0].inFlight == nil)
        let log = try OSLogStore(scope: .currentProcessIdentifier)
        let entries = try log.getEntries(at: log.position(date: since), matching: NSPredicate(format: "subsystem == 'Raccoon'"))
        #expect(entries.contains { $0.composedMessage.contains("Session not written on quit") && $0.composedMessage.contains(directory.path) })
    }
}

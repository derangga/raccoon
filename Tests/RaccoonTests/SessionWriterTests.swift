import Foundation
@testable import Raccoon
import RaccoonData
import RaccoonDomain
import RaccoonTesting
import Testing

@MainActor
final class SessionWriterTests {
    let directory = FileManager.default.temporaryDirectory.appending(path: "raccoon-\(UUID())")
    var store: DiskSessionStore { DiskSessionStore(directory: directory, root: directory.appending(path: "Raccoon").path) }
    var session = Session(tabs: [], selected: nil, activeEnvironment: nil)
    var writes = 0

    func writer(interval: Duration = .seconds(1)) -> SessionWriter {
        SessionWriter(store: store, instants: FixedInstantSource(.now), interval: interval) { [unowned self] in
            writes += 1
            return session
        }
    }

    func written() throws -> Session? { try store.read().map(SessionFile.decode) }

    @Test func `50 schedules within a second are one write`() throws {
        let writer = writer()
        for _ in 0..<50 { writer.schedule() }
        #expect(writes == 1)
        #expect(try written() == session)
        writer.pending?.cancel()
    }

    @Test func `a change inside the second is written when it is over, latest first`() async throws {
        let writer = writer(interval: .milliseconds(20))
        writer.schedule()
        session.activeEnvironment = "Staging"
        writer.schedule()
        session.activeEnvironment = "Prod"
        writer.schedule()
        #expect(try written()?.activeEnvironment == nil)

        await writer.pending?.value
        #expect(writes == 2)
        #expect(try written()?.activeEnvironment == "Prod")
    }

    @Test func `writeNow writes at once and replaces the pending write`() async throws {
        let writer = writer(interval: .milliseconds(20))
        writer.schedule()
        writer.schedule()
        session.activeEnvironment = "Prod"
        try writer.writeNow()
        #expect(try written()?.activeEnvironment == "Prod")
        #expect(writer.pending == nil)
        try await Task.sleep(for: .milliseconds(40))
        #expect(writes == 2)
    }

    @Test func `a Tab change in the window writes the Session`() async throws {
        let window = WindowModel(
            dataFolder: .test(directory.appending(path: "Raccoon")), folderWatch: ManualFolderWatch(),
            sessionStore: store, secrets: InMemorySecretStore(), instants: FixedInstantSource(.now),
            makeTab: {
                TabModel(transport: ScriptedTransport(.failure(.timedOut)), secrets: InMemorySecretStore(), files: DictionaryFileReading([:]),
                         instants: FixedInstantSource(.now), clipboard: RecordingClipboardWriter())
            }
        )
        #expect(try written() == nil)
        window.newTab()
        window.tabs[1].typeInURLBar("https://api.example.com")
        await Task.yield()

        let session = try #require(try written())
        #expect(session.tabs.map(\.id) == window.tabs.map(\.tab.id))
        #expect(session.tabs[1].definition.url == "https://api.example.com")
        #expect(session.selected == window.tabs[1].tab.id)
    }
}

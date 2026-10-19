import Foundation
import RaccoonData
import RaccoonDomain
import Testing

struct DiskSessionStoreTests {
    /// Not created yet: the store makes it on first write.
    let directory = FileManager.default.temporaryDirectory.appending(path: "raccoon-\(UUID())/Raccoon")

    @Test func `read with no file returns nil`() throws {
        #expect(try DiskSessionStore(directory: directory).read() == nil)
    }

    @Test func `write then read returns the same bytes`() throws {
        let store = DiskSessionStore(directory: directory)
        defer { try? FileManager.default.removeItem(at: directory.deletingLastPathComponent()) }

        try store.write(Data(#"{"version":1}"#.utf8))

        #expect(try store.read() == Data(#"{"version":1}"#.utf8))
        #expect(store.file == directory.appending(path: "session.json"))
    }

    @Test func `the live file is Application Support/Raccoon/session.json`() {
        let store = DiskSessionStore(directory: DiskSessionStore.applicationSupportDirectory)
        #expect(store.file.path.hasSuffix("/Library/Application Support/Raccoon/session.json"))
    }

    @Test func `setAside renames the file with the date and keeps its bytes`() throws {
        let noon = try Date("2026-10-19T09:15:00Z", strategy: .iso8601)
        let store = DiskSessionStore(directory: directory, clock: { noon })
        defer { try? FileManager.default.removeItem(at: directory.deletingLastPathComponent()) }
        try store.write(Data("not json".utf8))

        let path = try store.setAside()

        #expect(path == directory.appending(path: "session.corrupt-2026-10-19T091500Z.json").path)
        #expect(FileManager.default.contents(atPath: path) == Data("not json".utf8))
        #expect(try store.read() == nil)
    }

    @Test func `setAside with no file throws unwritable`() {
        let store = DiskSessionStore(directory: directory)
        #expect(throws: StoreError.self) { try store.setAside() }
    }
}

import Foundation
import RaccoonData
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
}

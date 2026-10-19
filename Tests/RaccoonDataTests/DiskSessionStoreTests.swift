import Foundation
import RaccoonData
import RaccoonDomain
import Testing

struct DiskSessionStoreTests {
    /// Not created yet: the store makes it on first write.
    let directory = FileManager.default.temporaryDirectory.appending(path: "raccoon-\(UUID())/Raccoon")

    func store(_ root: String = "/Users/me/Raccoon", clock: @escaping @Sendable () -> Date = Date.init) -> DiskSessionStore {
        DiskSessionStore(directory: directory, root: root, clock: clock)
    }

    @Test func `read with no file returns nil`() throws {
        #expect(try store().read() == nil)
    }

    @Test func `write then read returns the same bytes`() throws {
        defer { try? FileManager.default.removeItem(at: directory.deletingLastPathComponent()) }

        try store().write(Data(#"{"version":1}"#.utf8))

        #expect(try store().read() == Data(#"{"version":1}"#.utf8))
    }

    @Test func `the file is sessions slash the first 16 hex digits of SHA-256 of the root`() {
        // printf %s /Users/me/Raccoon | shasum -a 256
        #expect(store().file == directory.appending(path: "sessions/2d93ae20fc4c90c4.json"))
    }

    @Test func `the live file is in Application Support/Raccoon/sessions`() {
        let store = DiskSessionStore(directory: DiskSessionStore.applicationSupportDirectory, root: "/Users/me/Raccoon")
        #expect(store.file.path.hasSuffix("/Library/Application Support/Raccoon/sessions/2d93ae20fc4c90c4.json"))
    }

    @Test func `two roots write two files and never read each other's bytes`() throws {
        defer { try? FileManager.default.removeItem(at: directory.deletingLastPathComponent()) }

        try store("/Users/me/work/api").write(Data("work".utf8))
        try store("/Users/me/side/api").write(Data("side".utf8))

        #expect(try store("/Users/me/work/api").read() == Data("work".utf8))
        #expect(try store("/Users/me/side/api").read() == Data("side".utf8))
        #expect(try store("/Users/me/other").read() == nil)
    }

    @Test(arguments: ["/Users/me/Raccoon/", "/Users/me/./Raccoon", "/Users/me/x/../Raccoon"])
    func `the same path spelled differently gives the same file`(spelling: String) {
        #expect(store(spelling).file == store("/Users/me/Raccoon").file)
    }

    @Test func `setAside renames the file with the date and keeps its bytes`() throws {
        let noon = try Date("2026-10-19T09:15:00Z", strategy: .iso8601)
        let store = store(clock: { noon })
        defer { try? FileManager.default.removeItem(at: directory.deletingLastPathComponent()) }
        try store.write(Data("not json".utf8))

        let path = try store.setAside()

        #expect(path == directory.appending(path: "sessions/2d93ae20fc4c90c4.corrupt-2026-10-19T091500Z.json").path)
        #expect(FileManager.default.contents(atPath: path) == Data("not json".utf8))
        #expect(try store.read() == nil)
    }

    @Test func `setAside with no file throws unwritable`() {
        #expect(throws: StoreError.self) { try store().setAside() }
    }

    @Test func `delete removes the file, and deleting a missing file is not an error`() throws {
        defer { try? FileManager.default.removeItem(at: directory.deletingLastPathComponent()) }
        try store().write(Data("x".utf8))

        try store().delete()
        try store().delete()

        #expect(try store().read() == nil)
    }
}

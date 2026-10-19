import Foundation
import RaccoonData
import RaccoonDomain
import Testing

/// Each test gets a fresh temp root, the §9 test implementation of DataFolderStore.
final class DiskDataFolderStoreTests {
    let root = FileManager.default.temporaryDirectory.appending(path: "raccoon-\(UUID())")
    let store: DiskDataFolderStore

    init() throws {
        store = DiskDataFolderStore(root: root)
        try store.ensureExists()
    }

    deinit {
        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: root.path)
        try? FileManager.default.removeItem(at: root)
    }

    func put(_ text: String, at path: String) throws {
        let url = root.appending(path: path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
    }

    @Test func `ensureExists on a read-only root throws unwritable`() throws {
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: root.path)
        #expect {
            try store.ensureExists()
        } throws: { error in
            guard case .unwritable = error as? StoreError else { return false }
            return true
        }
    }

    @Test func `scan finds nested json files and skips the rest`() throws {
        try put("1", at: "globals.json")
        try put("2", at: "Payments API/Refunds/List refunds.json")
        try put("x", at: "Payments API/notes.txt")
        try put("h", at: ".git/config.json")
        try store.createDirectory("Empty/Nested")

        #expect(try store.scan() == DataFolderScan(
            files: ["globals.json": Data("1".utf8), "Payments API/Refunds/List refunds.json": Data("2".utf8)],
            folders: ["Payments API", "Payments API/Refunds", "Empty", "Empty/Nested"]
        ))
    }

    @Test func `a write into a read-only folder says permission denied`() throws {
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: root.path)
        #expect(throws: StoreError.unwritable(path: "a.json", reason: "permission denied")) {
            try store.write(Data("{}".utf8), to: "a.json")
        }
    }

    @Test func `read returns what write wrote`() throws {
        try store.createDirectory("Payments API")
        try store.write(Data("{}".utf8), to: "Payments API/Create charge.json")

        #expect(try store.read("Payments API/Create charge.json") == Data("{}".utf8))
    }

    @Test func `a failed write leaves the old file whole`() throws {
        try put("old", at: "C/r.json")
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: root.appending(path: "C").path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: root.appending(path: "C").path) }

        #expect(throws: StoreError.self) { try store.write(Data("new".utf8), to: "C/r.json") }
        #expect(try store.read("C/r.json") == Data("old".utf8))
    }

    @Test func `move renames and never overwrites`() throws {
        try put("a", at: "C/a.json")
        try put("b", at: "C/b.json")

        try store.move("C/a.json", to: "C/c.json")
        #expect(try store.read("C/c.json") == Data("a".utf8))
        #expect(throws: StoreError.self) { try store.move("C/c.json", to: "C/b.json") }
        #expect(try store.read("C/b.json") == Data("b".utf8))
    }

    @Test func `trash moves the file to the Trash`() throws {
        let name = "\(UUID()).json"
        try put("t", at: "C/\(name)")

        try store.trash("C/\(name)")

        #expect(!FileManager.default.fileExists(atPath: root.appending(path: "C/\(name)").path))
        let trashed = try FileManager.default.url(for: .trashDirectory, in: .userDomainMask, appropriateFor: root, create: false)
            .appending(path: name)
        #expect(FileManager.default.fileExists(atPath: trashed.path))
        try? FileManager.default.removeItem(at: trashed)
    }

    @Test func `writeDirectory lands the whole folder`() throws {
        try store.writeDirectory(["r.json": Data("1".utf8), "F/x.json": Data("2".utf8)], to: "Imported")

        #expect(try store.scan().files == ["Imported/r.json": Data("1".utf8), "Imported/F/x.json": Data("2".utf8)])
        #expect(try FileManager.default.contentsOfDirectory(atPath: root.path) == ["Imported"])
    }

    @Test func `writeDirectory leaves nothing when a write inside it fails`() throws {
        // a.json cannot be both a file and the folder holding b.json, in either order.
        let files = ["a.json": Data("1".utf8), "a.json/b.json": Data("2".utf8)]

        #expect(throws: StoreError.self) { try store.writeDirectory(files, to: "Imported") }
        #expect(try FileManager.default.contentsOfDirectory(atPath: root.path).isEmpty)
    }
}

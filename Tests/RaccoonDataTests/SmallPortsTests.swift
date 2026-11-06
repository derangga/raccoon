import AppKit
import Foundation
import RaccoonData
import RaccoonDomain
import Testing

struct SmallPortsTests {
    @Test func `disk file reading returns a file's bytes`() throws {
        let file = FileManager.default.temporaryDirectory.appending(path: "\(UUID()).bin")
        try Data([0, 1, 255]).write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }

        #expect(try DiskFileReading().read(file.path) == Data([0, 1, 255]))
    }

    @Test func `disk file reading throws unreadable for a missing path`() {
        let path = FileManager.default.temporaryDirectory.appending(path: "\(UUID()).bin").path
        #expect {
            try DiskFileReading().read(path)
        } throws: { error in
            guard case .unreadable(path, _) = error as? StoreError else { return false }
            return true
        }
    }

    @Test func `system clipboard writer round-trips a string through NSPasteboard`() {
        let name = NSPasteboard.Name("raccoon-test-\(UUID())")
        defer { NSPasteboard(name: name).releaseGlobally() }

        SystemClipboardWriter(name: name).setString("curl 'https://example.com'")

        #expect(NSPasteboard(name: name).string(forType: .string) == "curl 'https://example.com'")
    }

    @Test func `continuous instant source never goes backwards`() {
        let source = ContinuousInstantSource()
        let first = source.now
        let second = source.now
        #expect(first <= second)
    }

    // DiskFileWriting over a temp dir: the two facts a recording fake cannot show.
    @Test func `disk file writing writes the bytes, and replaces a file already there`() throws {
        let dir = try makeTempDir()
        defer { removeTempDir(dir) }
        let file = dir.appending(path: "a.json")

        try DiskFileWriting().write(Data("one".utf8), to: file)
        try DiskFileWriting().write(Data("two".utf8), to: file)

        #expect(try Data(contentsOf: file) == Data("two".utf8))
    }

    // Root ignores folder permissions, so the write would succeed.
    @Test(.enabled(if: getuid() != 0)) func `disk file writing leaves the old file as it was when the write fails`() throws {
        let dir = try makeTempDir()
        defer { removeTempDir(dir) }
        let file = dir.appending(path: "a.json")
        try Data("old".utf8).write(to: file)
        // The file itself stays writable: only a write that goes through a temp file in the folder fails.
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: dir.path)

        #expect(throws: StoreError.self) { try DiskFileWriting().write(Data("new".utf8), to: file) }
        #expect(try Data(contentsOf: file) == Data("old".utf8))
    }

    // Root ignores folder permissions, so the write would succeed.
    @Test(.enabled(if: getuid() != 0)) func `disk file writing into a folder that is not writable throws unwritable with the reason`() throws {
        let dir = try makeTempDir()
        defer { removeTempDir(dir) }
        let file = dir.appending(path: "a.json")
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: dir.path)

        #expect(throws: StoreError.unwritable(path: file.path, reason: "permission denied")) {
            try DiskFileWriting().write(Data("x".utf8), to: file)
        }
    }

    private func makeTempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appending(path: "raccoon-\(UUID())")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Permissions come back first, or the folder cannot be removed.
    private func removeTempDir(_ dir: URL) {
        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: dir.path)
        try? FileManager.default.removeItem(at: dir)
    }
}

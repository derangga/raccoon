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
}

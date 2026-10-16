import Foundation
import Testing

/// Only the resolver can build a ResolvedRequest, so a request with an Undefined Variable cannot
/// reach the transport. This type-checks code outside RaccoonDomain against the built module.
private final class BundleMarker {}

struct ResolvedRequestAccessTests {
    static func typecheck(_ source: String) throws -> (succeeded: Bool, output: String) {
        // The built modules sit next to this test bundle.
        let modules = Bundle(for: BundleMarker.self).bundleURL.deletingLastPathComponent()
        let file = FileManager.default.temporaryDirectory.appending(path: "\(UUID()).swift")
        try source.write(to: file, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: file) }

        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(filePath: "/usr/bin/xcrun")
        process.arguments = ["swiftc", "-typecheck", "-target", "arm64-apple-macos15.0", "-I", modules.path, file.path]
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        let output = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        process.waitUntilExit()
        return (process.terminationStatus == 0, output)
    }

    @Test func `public shapes type-check outside RaccoonDomain`() throws {
        let result = try Self.typecheck("import RaccoonDomain\nlet d = RequestDefinition.empty\n")
        #expect(result.succeeded, "\(result.output)")
    }

    @Test func `ResolvedRequest cannot be built outside RaccoonDomain`() throws {
        let result = try Self.typecheck("import RaccoonDomain\nlet r = ResolvedRequest(definition: .empty)\n")
        #expect(!result.succeeded)
        #expect(result.output.contains("inaccessible") || result.output.contains("no accessible initializers"), "\(result.output)")
    }
}

import Foundation
import Testing

/// RaccoonDomain holds no I/O: a rule that wants a file reads it through a port.
struct LayeringTests {
    static let forbidden = ["FileManager", "URLSession", "import Security", "import CoreServices"]

    static func violations(in source: String) -> [String] {
        source.split(separator: "\n", omittingEmptySubsequences: false).enumerated().compactMap { index, line in
            let code = line.trimmingCharacters(in: .whitespaces)
            guard !code.hasPrefix("//"), let name = forbidden.first(where: code.contains) else { return nil }
            return "line \(index + 1): \(name)"
        }
    }

    @Test(arguments: [
        ("let fm = FileManager.default", ["line 1: FileManager"]),
        ("import Foundation\nlet s = URLSession.shared", ["line 2: URLSession"]),
        ("import Security", ["line 1: import Security"]),
        ("import CoreServices", ["line 1: import CoreServices"]),
        ("// what URLSession adds", []),
        ("import Foundation\nlet url: URL? = nil", []),
    ])
    func `flags each forbidden name`(source: String, expected: [String]) {
        #expect(Self.violations(in: source) == expected)
    }

    @Test func `RaccoonDomain does no I/O`() throws {
        let root = URL(filePath: #filePath).deletingLastPathComponent()
            .appending(path: "../../Sources/RaccoonDomain").standardized
        let files = try #require(FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil))
            .compactMap { $0 as? URL }
            .filter { $0.pathExtension == "swift" }
        #expect(!files.isEmpty)
        for file in files {
            let found = Self.violations(in: try String(contentsOf: file, encoding: .utf8))
            #expect(found.isEmpty, "\(file.lastPathComponent): \(found)")
        }
    }
}

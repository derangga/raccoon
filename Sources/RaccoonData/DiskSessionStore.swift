import Foundation
import RaccoonDomain

/// session.json, outside the Data Folder: it holds Drafts and unsaved edits, which must never
/// show up in `git status`. Bytes only; SessionFile owns the format.
public struct DiskSessionStore: SessionStore {
    public let file: URL

    public init(directory: URL) {
        file = directory.appending(path: "session.json")
    }

    public static var applicationSupportDirectory: URL {
        URL.applicationSupportDirectory.appending(path: "Raccoon")
    }

    public func read() throws(StoreError) -> Data? {
        guard FileManager.default.fileExists(atPath: file.path) else { return nil }
        return try lifting({ .unreadable(path: file.path, reason: $0) }) { try Data(contentsOf: file) }
    }

    public func write(_ data: Data) throws(StoreError) {
        try lifting({ .unwritable(path: file.path, reason: $0) }) {
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: file, options: .atomic)
        }
    }
}

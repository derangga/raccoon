import Foundation
import RaccoonDomain

/// session.json, outside the Data Folder: it holds Drafts and unsaved edits, which must never
/// show up in `git status`. Bytes only; SessionFile owns the format.
public struct DiskSessionStore: SessionStore {
    public let file: URL
    /// The date in a set-aside file's name.
    private let clock: @Sendable () -> Date

    public init(directory: URL, clock: @escaping @Sendable () -> Date = Date.init) {
        file = directory.appending(path: "session.json")
        self.clock = clock
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

    /// Never deleted: the user may want what was in it.
    public func setAside() throws(StoreError) -> String {
        let stamp = clock().formatted(.iso8601.timeSeparator(.omitted))
        let aside = file.deletingLastPathComponent().appending(path: "session.corrupt-\(stamp).json")
        try lifting({ .unwritable(path: aside.path, reason: $0) }) { try FileManager.default.moveItem(at: file, to: aside) }
        return aside.path
    }
}

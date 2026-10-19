import CryptoKit
import Foundation
import RaccoonDomain

/// One Workspace's Session, outside its Data Folder: it holds Drafts and unsaved edits, which
/// must never show up in `git status`. The file is sessions/<key>.json, the key the first 16 hex
/// digits of SHA-256 of the standardized root, so the Session follows the path: two clones of
/// one repository keep two sets of Tabs. Bytes only; SessionFile owns the format.
public struct DiskSessionStore: SessionStore {
    public let file: URL
    /// The date in a set-aside file's name.
    private let clock: @Sendable () -> Date

    public init(directory: URL, root: String, clock: @escaping @Sendable () -> Date = Date.init) {
        let path = URL(filePath: root).standardized.path
        let key = SHA256.hash(data: Data(path.utf8)).prefix(8).map { String(format: "%02x", $0) }.joined()
        file = directory.appending(path: "sessions/\(key).json")
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
        let aside = file.deletingPathExtension().appendingPathExtension("corrupt-\(stamp).json")
        try lifting({ .unwritable(path: aside.path, reason: $0) }) { try FileManager.default.moveItem(at: file, to: aside) }
        return aside.path
    }

    public func delete() throws(StoreError) {
        guard FileManager.default.fileExists(atPath: file.path) else { return }
        try lifting({ .unwritable(path: file.path, reason: $0) }) { try FileManager.default.removeItem(at: file) }
    }
}

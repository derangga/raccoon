import Foundation
import RaccoonDomain

/// The Data Folder on disk. Every path is relative to the root.
public struct DiskDataFolderStore: DataFolderStore {
    private let root: URL

    public init(root: URL) {
        self.root = root
    }

    private func url(_ path: String) -> URL { root.appending(path: path) }

    public func ensureExists() throws(StoreError) {
        let unwritable = { (reason: String) in StoreError.unwritable(path: root.path, reason: reason) }
        try lifting(unwritable) { try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true) }
        guard FileManager.default.isWritableFile(atPath: root.path) else { throw unwritable("The folder is not writable.") }
    }

    /// Skips hidden files and folders: `.git`, and writeDirectory's temp folder mid-write.
    public func scan() throws(StoreError) -> DataFolderScan {
        // ponytail: one unreadable file fails the whole scan; [path: Data] has no slot for it.
        // Upgrade when a permission-denied file in a cloned repo should show as one bad row.
        try lifting({ .unreadable(path: root.path, reason: $0) }) {
            let rootPath = root.standardizedFileURL.path + "/"
            var files: [String: Data] = [:]
            var folders: Set<String> = []
            var enumerationError: (any Error)?
            let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isDirectoryKey], options: .skipsHiddenFiles) { _, error in
                enumerationError = error
                return false
            }
            while let item = enumerator?.nextObject() as? URL {
                let path = String(item.standardizedFileURL.path.dropFirst(rootPath.count))
                if try item.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true {
                    folders.insert(path)
                } else if item.pathExtension == "json" {
                    files[path] = try Data(contentsOf: item)
                }
            }
            if let enumerationError { throw enumerationError }
            return DataFolderScan(files: files, folders: folders)
        }
    }

    public func read(_ path: String) throws(StoreError) -> Data {
        try lifting({ .unreadable(path: path, reason: $0) }) { try Data(contentsOf: url(path)) }
    }

    public func write(_ data: Data, to path: String) throws(StoreError) {
        try lifting({ .unwritable(path: path, reason: $0) }) { try data.write(to: url(path), options: .atomic) }
    }

    public func move(_ path: String, to newPath: String) throws(StoreError) {
        try lifting({ .unwritable(path: path, reason: $0) }) { try FileManager.default.moveItem(at: url(path), to: url(newPath)) }
    }

    public func trash(_ path: String) throws(StoreError) {
        try lifting({ .unwritable(path: path, reason: $0) }) { try FileManager.default.trashItem(at: url(path), resultingItemURL: nil) }
    }

    public func createDirectory(_ path: String) throws(StoreError) {
        try lifting({ .unwritable(path: path, reason: $0) }) {
            try FileManager.default.createDirectory(at: url(path), withIntermediateDirectories: true)
        }
    }

    public func writeDirectory(_ contents: DataFolderScan, to path: String) throws(StoreError) {
        let temp = root.appending(path: ".raccoon-\(UUID())")
        defer { try? FileManager.default.removeItem(at: temp) }
        try lifting({ .unwritable(path: path, reason: $0) }) {
            try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: false)
            for folder in contents.folders {
                try FileManager.default.createDirectory(at: temp.appending(path: folder), withIntermediateDirectories: true)
            }
            for (file, data) in contents.files {
                let target = temp.appending(path: file)
                try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
                try data.write(to: target)
            }
            // moveItem refuses a destination that exists, so nothing is written over.
            try FileManager.default.moveItem(at: temp, to: url(path))
        }
    }
}

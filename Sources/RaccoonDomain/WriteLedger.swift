import CryptoKit
import Foundation

/// The files Raccoon wrote, by the SHA-256 of their bytes, so FolderWatch can drop its own
/// writes. Hashes rather than timestamps: a git checkout that restores identical bytes is a
/// no-op too. nil bytes is a path Raccoon removed, or a folder: ours while it reads as nothing.
public struct WriteLedger: Sendable {
    private var hashes: [String: SHA256.Digest?] = [:]

    public init() {}

    public mutating func record(_ path: String, _ bytes: Data?) {
        hashes[path] = .some(bytes.map { SHA256.hash(data: $0) })
    }

    /// `bytes` is what the path holds now: nil when it is gone or a folder.
    public func isOurs(_ path: String, _ bytes: Data?) -> Bool {
        guard let recorded = hashes[path] else { return false }
        return recorded == bytes.map { SHA256.hash(data: $0) }
    }
}

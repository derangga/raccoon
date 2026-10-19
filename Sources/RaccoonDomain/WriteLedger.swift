import CryptoKit
import Foundation

/// The files Raccoon wrote, by the SHA-256 of their bytes, so FolderWatch can drop its own
/// writes. Hashes rather than timestamps: a git checkout that restores identical bytes is a
/// no-op too.
public struct WriteLedger: Sendable {
    private var hashes: [String: SHA256.Digest] = [:]

    public init() {}

    public mutating func record(_ path: String, _ bytes: Data) {
        hashes[path] = SHA256.hash(data: bytes)
    }

    public func isOurs(_ path: String, _ bytes: Data) -> Bool {
        hashes[path] == SHA256.hash(data: bytes)
    }
}

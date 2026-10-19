import Foundation

// Each port has one live implementation in RaccoonData and one test implementation in
// RaccoonTesting. None has a shared instance: the composition root builds them once.

public protocol HTTPTransport: Sendable {
    /// Never retries: Raccoon cannot know whether a POST that timed out was applied.
    func send(_ request: ResolvedRequest) async throws(SendError) -> Response
}

/// `@file` references in a Curl Import and multipart file parts.
public protocol FileReading: Sendable {
    func read(_ path: String) throws(StoreError) -> Data
}

/// The Data Folder. The root is given to init; every path is relative to it.
public protocol DataFolderStore: Sendable {
    func ensureExists() throws(StoreError)
    /// Every `.json` file and every folder under the root.
    func scan() throws(StoreError) -> DataFolderScan
    func read(_ path: String) throws(StoreError) -> Data
    /// Atomic: the file is whole or untouched.
    func write(_ data: Data, to path: String) throws(StoreError)
    func move(_ path: String, to newPath: String) throws(StoreError)
    /// To the Trash, never unlinked.
    func trash(_ path: String) throws(StoreError)
    func createDirectory(_ path: String) throws(StoreError)
    /// Written to a hidden temp folder in the root, then renamed into place: whole or nothing.
    func writeDirectory(_ files: [String: Data], to path: String) throws(StoreError)
}

public protocol FolderWatch: Sendable {
    /// Changed paths, in batches, until the consumer stops iterating.
    func events(root: String) -> AsyncStream<[String]>
}

/// The Keychain. An `environment` of nil is Globals.
public protocol SecretStore: Sendable {
    func get(environment: String?, name: VariableName) throws(SecretError) -> String?
    func set(_ value: String, environment: String?, name: VariableName) throws(SecretError)
    func delete(environment: String?, name: VariableName) throws(SecretError)
}

/// One Workspace's Session file, bytes only; SessionFile owns the format. nil when there is no
/// file yet.
public protocol SessionStore: Sendable {
    func read() throws(StoreError) -> Data?
    func write(_ data: Data) throws(StoreError)
    /// Renames an undecodable file to <key>.corrupt-<date>.json and returns its new path.
    func setAside() throws(StoreError) -> String
    /// Remove from List. No file is not an error.
    func delete() throws(StoreError)
}

public protocol ClipboardWriter: Sendable {
    func setString(_ string: String)
}

/// Where `.sending(since:)` gets its instant.
public protocol InstantSource: Sendable {
    var now: ContinuousClock.Instant { get }
}

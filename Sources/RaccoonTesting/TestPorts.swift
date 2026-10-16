import Foundation
import RaccoonDomain
import Synchronization

/// Returns a canned Response or SendError, and records every ResolvedRequest it was given.
public final class ScriptedTransport: HTTPTransport {
    private let result: Result<Response, SendError>
    private let sent = Mutex<[ResolvedRequest]>([])

    public init(_ result: Result<Response, SendError>) {
        self.result = result
    }

    public var requests: [ResolvedRequest] { sent.withLock { $0 } }

    public func send(_ request: ResolvedRequest) async throws(SendError) -> Response {
        sent.withLock { $0.append(request) }
        return try result.get()
    }
}

public struct DictionaryFileReading: FileReading {
    private let files: [String: Data]

    public init(_ files: [String: Data]) {
        self.files = files
    }

    public func read(_ path: String) throws(StoreError) -> Data {
        guard let data = files[path] else { throw .unreadable(path: path, reason: "No such file") }
        return data
    }
}

/// Delivers exactly what the test passes to `emit`, to every stream still being iterated.
public final class ManualFolderWatch: FolderWatch {
    private let continuations = Mutex<[UUID: AsyncStream<[String]>.Continuation]>([:])

    public init() {}

    public func events(root: String) -> AsyncStream<[String]> {
        let (stream, continuation) = AsyncStream<[String]>.makeStream()
        let id = UUID()
        continuations.withLock { $0[id] = continuation }
        continuation.onTermination = { [weak self] _ in
            _ = self?.continuations.withLock { $0.removeValue(forKey: id) }
        }
        return stream
    }

    public func emit(_ paths: [String]) {
        for continuation in continuations.withLock({ Array($0.values) }) {
            continuation.yield(paths)
        }
    }
}

public final class InMemorySecretStore: SecretStore {
    private struct Key: Hashable {
        var environment: String?
        var name: VariableName
    }

    private let values = Mutex<[Key: String]>([:])

    public init() {}

    public func get(environment: String?, name: VariableName) throws(SecretError) -> String? {
        values.withLock { $0[Key(environment: environment, name: name)] }
    }

    public func set(_ value: String, environment: String?, name: VariableName) throws(SecretError) {
        values.withLock { $0[Key(environment: environment, name: name)] = value }
    }

    public func delete(environment: String?, name: VariableName) throws(SecretError) {
        _ = values.withLock { $0.removeValue(forKey: Key(environment: environment, name: name)) }
    }
}

public final class RecordingClipboardWriter: ClipboardWriter {
    private let last = Mutex<String?>(nil)

    public init() {}

    public var string: String? { last.withLock { $0 } }

    public func setString(_ string: String) {
        last.withLock { $0 = string }
    }
}

public struct FixedInstantSource: InstantSource {
    public let now: ContinuousClock.Instant

    public init(_ now: ContinuousClock.Instant) {
        self.now = now
    }
}

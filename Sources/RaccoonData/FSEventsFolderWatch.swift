import CoreServices
import Foundation
import RaccoonDomain
import Synchronization

/// The Data Folder watch. FSEvents' 300 ms latency is the coalescing: a git checkout of 200 files
/// arrives as one batch. Paths are relative to the root, like DataFolderStore's.
public final class FSEventsFolderWatch: FolderWatch {
    private let live = Mutex(0)

    public init() {}

    /// FSEventStreams not yet invalidated, for tests.
    var liveStreams: Int { live.withLock { $0 } }

    public func events(root: String) -> AsyncStream<[String]> {
        let (stream, continuation) = AsyncStream<[String]>.makeStream()
        let queue = DispatchQueue(label: "FSEventsFolderWatch")
        // FSEvents reports real paths (/private/var/…); Foundation's resolvingSymlinksInPath strips /private.
        let prefix = (realpath(root, nil).map { defer { free($0) }; return String(cString: $0) } ?? root) + "/"
        let sink = Sink(queue: queue) { paths in
            var seen = Set<String>()
            let batch = paths.filter { $0.hasPrefix(prefix) }.map { String($0.dropFirst(prefix.count)) }.filter { seen.insert($0).inserted }
            if !batch.isEmpty { continuation.yield(batch) }
        }
        var context = FSEventStreamContext(version: 0, info: Unmanaged.passUnretained(sink).toOpaque(), retain: nil, release: nil, copyDescription: nil)
        let flags = FSEventStreamCreateFlags(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagUseCFTypes)
        guard let eventStream = FSEventStreamCreate(nil, { _, info, _, paths, _, _ in
            // With kFSEventStreamCreateFlagUseCFTypes, paths is a CFArray of CFString.
            Unmanaged<Sink>.fromOpaque(info!).takeUnretainedValue().receive(unsafeBitCast(paths, to: NSArray.self) as? [String] ?? [])
        }, &context, [root] as CFArray, FSEventStreamEventId(kFSEventStreamEventIdSinceNow), 0.3, flags) else {
            continuation.finish()
            return stream
        }

        nonisolated(unsafe) let unsafeStream = eventStream
        FSEventStreamSetDispatchQueue(eventStream, queue)
        FSEventStreamStart(eventStream)
        live.withLock { $0 += 1 }

        // Torn down on the stream's own queue, so no callback runs mid-release; capturing sink
        // keeps it alive until then.
        continuation.onTermination = { [self] _ in
            queue.async {
                FSEventStreamStop(unsafeStream)
                FSEventStreamInvalidate(unsafeStream)
                FSEventStreamRelease(unsafeStream)
                withExtendedLifetime(sink) {}
                self.live.withLock { $0 -= 1 }
            }
        }
        return stream
    }
}

/// The FSEvents callback's context: a C function pointer cannot capture. FSEvents hands one
/// latency window to the callback in chunks of 32 paths, each its own block on the queue but
/// all within about a millisecond, so chunks are collected and flushed as one batch 50 ms after
/// the first.
private final class Sink: Sendable {
    private let queue: DispatchQueue
    private let flush: @Sendable ([String]) -> Void
    private let pending = Mutex<[String]?>(nil)

    init(queue: DispatchQueue, flush: @escaping @Sendable ([String]) -> Void) {
        self.queue = queue
        self.flush = flush
    }

    func receive(_ paths: [String]) {
        let isFirstChunk = pending.withLock { pending in
            defer { pending = (pending ?? []) + paths }
            return pending == nil
        }
        guard isFirstChunk else { return }
        queue.asyncAfter(deadline: .now() + .milliseconds(50)) { [self] in
            if let batch = pending.withLock({ pending in defer { pending = nil }; return pending }) { flush(batch) }
        }
    }
}

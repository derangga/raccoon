import Foundation
@testable import RaccoonData
import Testing

/// FSEvents over a real temp folder. Timing-based by nature: each wait is bounded.
struct FSEventsFolderWatchTests {
    let root = FileManager.default.temporaryDirectory.appending(path: "raccoon-watch-\(UUID())")

    init() throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    /// The stream's first batch, or nil after `timeout`. Ends the stream either way.
    func firstBatch(_ stream: AsyncStream<[String]>, timeout: Duration = .seconds(5)) async -> [String]? {
        await withTaskGroup(of: [String]?.self) { group in
            group.addTask { var iterator = stream.makeAsyncIterator(); return await iterator.next() }
            group.addTask { try? await Task.sleep(for: timeout); return nil }
            defer { group.cancelAll() }
            return await group.next() ?? nil
        }
    }

    @Test func `200 files written at once arrive as one batch of relative paths`() async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let watch = FSEventsFolderWatch()
        let stream = watch.events(root: root.path)
        try await Task.sleep(for: .milliseconds(200))

        let names = (0..<200).map { "Collection/r\($0).json" }
        try FileManager.default.createDirectory(at: root.appending(path: "Collection"), withIntermediateDirectories: true)
        for name in names { try Data("{}".utf8).write(to: root.appending(path: name)) }

        let batch = try #require(await firstBatch(stream))
        #expect(Set(names).isSubset(of: Set(batch)))
        #expect(batch.allSatisfy { !$0.hasPrefix("/") && !$0.hasPrefix("..") })
    }

    @Test func `cancelling the consumer stops and invalidates the FSEventStream`() async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let watch = FSEventsFolderWatch()
        let consumer = Task {
            for await _ in watch.events(root: root.path) {}
        }
        try await Task.sleep(for: .milliseconds(200))
        #expect(watch.liveStreams == 1)

        consumer.cancel()
        await consumer.value
        try await Task.sleep(for: .milliseconds(100))

        #expect(watch.liveStreams == 0)
    }
}

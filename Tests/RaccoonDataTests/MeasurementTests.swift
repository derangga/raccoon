import Darwin
import Foundation
@testable import RaccoonData
@testable import RaccoonDomain
import RaccoonTesting
import Testing

/// Too slow or too large for every run. `RACCOON_MEASURE=1 swift test --filter MeasurementTests`
/// prints what design/environment-facts.md records.
@Suite(.enabled(if: ProcessInfo.processInfo.environment["RACCOON_MEASURE"] == "1"), .serialized)
struct MeasurementTests {
    /// Peak resident memory of this process so far, in MB (ru_maxrss is bytes on macOS).
    static func peakMB() -> Double {
        var usage = rusage()
        getrusage(RUSAGE_SELF, &usage)
        return Double(usage.ru_maxrss) / 1_048_576
    }

    @Test(arguments: [100, 500])
    func `peak memory for a large response`(megabytes: Int) async throws {
        try await withEchoServer { server in
            let transport = URLSessionTransport(files: DictionaryFileReading([:]), timeout: .seconds(600))
            let before = Self.peakMB()
            let start = ContinuousClock.now

            let response = try await transport.send(ResolvedRequest(definition: .empty, url: server.url("/bytes/\(megabytes * 1_048_576)")))

            let elapsed = ContinuousClock.now - start
            let after = Self.peakMB()
            print("MEASURE \(megabytes) MB: byteCount \(response.byteCount), peak before \(before) MB, peak after \(after) MB, elapsed \(elapsed)")
            #expect(response.byteCount == megabytes * 1_048_576)
        }
    }
}

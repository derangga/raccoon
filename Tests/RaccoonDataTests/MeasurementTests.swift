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

    /// Q14: a keystroke in the Find panel, on a Pretty-sized and a Raw-only body.
    @Test(arguments: [5, 20])
    func `matching a body for the Find panel`(megabytes: Int) {
        let line = #"    "id": "big-pickle", "owned_by": "opencode", "created": 1794300781,"# + "\n"
        let text = String(repeating: line, count: megabytes * 1_000_000 / line.utf8.count) as NSString
        for query in ["e", "pickle", "1794300781", "zzqx"] {
            let start = ContinuousClock.now
            let matches = FindMatches(of: query, in: text)
            print("MEASURE find \(megabytes) MB \"\(query)\": \(matches.ranges.count)\(matches.capped ? "+" : "") matches in \(ContinuousClock.now - start)")
        }
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

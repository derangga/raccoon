import Foundation
import RaccoonDomain
import Testing

/// Off unless RACCOON_MEASURE=1: `RACCOON_MEASURE=1 swift test --filter FilterMeasurementTests`
/// prints what design/environment-facts.md records. Add `-c release` for the shipping numbers.
@Suite(.enabled(if: ProcessInfo.processInfo.environment["RACCOON_MEASURE"] == "1"), .serialized)
struct FilterMeasurementTests {
    /// 20 Collections × 50 Folders × 20 Requests: 21,020 names.
    static let tree = (0..<20).map { c in
        Collection(name: "Service number \(c)", nodes: (0..<50).map { f in
            .folder(name: "Folder of things \(f)", children: (0..<20).map { r in
                .request(TreeDecoderTests.id(c * 1000 + f * 20 + r), name: "Get customer invoice détail \(r)", method: "GET", path: "S\(c)/F\(f)/R\(r).json")
            })
        })
    }

    /// "xyzq" matches nothing, "cinv" every Request with gaps, "invoice" and "e" as substrings.
    @Test(arguments: ["xyzq", "cinv", "invoice", "e"])
    func `filter time over 21,020 names`(query: String) {
        let tree = Self.tree
        var count = 0
        let elapsed = ContinuousClock().measure { count = TreeFilter.matches(tree, query).matchCount }
        print("MEASURE \(query): \(elapsed), \(count) matches")
    }
}

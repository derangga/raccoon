import Foundation
import RaccoonDomain
import Testing

struct VariableTokensTests {
    /// (location, length, name) per token, UTF-16 as text storage counts.
    static let cases: [(String, [(Int, Int, String)])] = [
        ("{{a}}", [(0, 5, "a")]),
        ("{{ a }}", [(0, 7, "a")]),
        ("{{a}}{{b}}", [(0, 5, "a"), (5, 5, "b")]),
        ("{{base}}/users/{{id}}", [(0, 8, "base"), (15, 6, "id")]),
        ("{{a", []),
        ("{{a}", []),
        ("東京{{host}}の天気", [(2, 8, "host")]),
        ("😀{{x}}", [(2, 5, "x")]),
        ("{{{a}}}", [(1, 5, "a")]),
        ("{{a {{b}}", [(4, 5, "b")]),
        ("{{}} {{  }} {{a b}} {{$guid}}", []),
        ("{{api.v2_key-1}}", [(0, 16, "api.v2_key-1")]),
        ("no braces", []),
    ]

    @Test(arguments: cases)
    func `every {{name}} is found with its UTF-16 range and its name`(text: String, expected: [(Int, Int, String)]) {
        let tokens = VariableTokens.ranges(text)

        #expect(tokens.map { [$0.range.location, $0.range.length] } == expected.map { [$0.0, $0.1] })
        #expect(tokens.map(\.name.rawValue) == expected.map(\.2))
    }

    @Test func `a 1 MB body scans in under one frame`() {
        let text = String(repeating: #"{"id": "{{id}}", "name": "{{ name }}", "x": "{{x"},"#, count: 20_000)
        #expect(text.utf8.count > 1_000_000)

        let clock = ContinuousClock()
        var tokens: [VariableToken] = []
        let elapsed = clock.measure { tokens = VariableTokens.ranges(text) }

        #if DEBUG
        // shortcut: an unoptimized build runs this scan about 4× slower (27 ms against 7 ms), so
        // `swift test -c release` is the one-frame check; tighten if debug gets a faster loop.
        let budget = Duration.milliseconds(64)
        #else
        let budget = Duration.milliseconds(16)
        #endif
        #expect(tokens.count == 40_000)
        #expect(elapsed < budget, "took \(elapsed)")
    }
}

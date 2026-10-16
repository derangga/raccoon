import RaccoonDomain
import Testing

struct ResponseStateTests {
    let since = ContinuousClock.now

    @Test(arguments: [(0, false), (149, false), (150, true), (2_000, true)])
    func `the spinner shows only once a send has run 150 ms`(elapsed: Int, shown: Bool) {
        #expect(ResponseState.sending(since: since).showsSpinner(at: since + .milliseconds(elapsed)) == shown)
    }

    @Test func `no other state shows the spinner`() {
        let later = since + .seconds(5)
        #expect(!ResponseState.idle.showsSpinner(at: later))
        #expect(!ResponseState.failed(.timedOut, after: .zero).showsSpinner(at: later))
        #expect(!ResponseState.notSent(.invalidURL("x")).showsSpinner(at: later))
    }
}

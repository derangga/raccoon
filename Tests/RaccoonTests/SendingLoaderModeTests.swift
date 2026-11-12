import Foundation
@testable import Raccoon
import RaccoonDomain
import Testing

/// surfaces.md §7, Sending loader: play, still or hidden, from the Response state, Reduce Motion,
/// the body area's height and whether the asset loaded.
struct SendingLoaderModeTests {
    static let now = ContinuousClock.now

    static func sending(for age: Duration) -> ResponseState { .sending(since: now - age) }

    /// 16 + the 240 pt loader + 8 + one text line (16) + 16.
    static let tall = 296.0
    static let received = ResponseState.received(Response(status: 200, headers: [], body: Data(), elapsed: .zero, byteCount: 0))

    @Test(arguments: [
        // state, Reduce Motion, body height, asset loaded, expected
        (sending(for: .seconds(2)), false, tall, true, SendingLoaderMode.play),
        (sending(for: .seconds(2)), true, tall, true, .still),
        (sending(for: .milliseconds(150)), false, tall, true, .play),
        (sending(for: .milliseconds(149)), false, tall, true, .hidden),
        (sending(for: .zero), false, tall, true, .hidden),
        (sending(for: .zero), true, tall, true, .hidden),
        (sending(for: .seconds(2)), false, 295.9, true, .hidden),
        (sending(for: .seconds(2)), true, 115, true, .hidden),
        (sending(for: .seconds(2)), false, 600, true, .play),
        (sending(for: .seconds(2)), false, tall, false, .hidden),
        (sending(for: .seconds(2)), true, tall, false, .hidden),
        (.idle, false, 600, true, .hidden),
        (received, false, 600, true, .hidden),
        (.failed(.timedOut(seconds: 60), after: .seconds(60)), false, 600, true, .hidden),
        (.notSent(.invalidURL("x")), false, 600, true, .hidden),
    ])
    func `the loader plays, stands still or stays hidden`(
        state: ResponseState, reduceMotion: Bool, bodyHeight: Double, assetLoaded: Bool, expected: SendingLoaderMode
    ) {
        let mode = SendingLoaderMode.of(
            state, now: Self.now, reduceMotion: reduceMotion, bodyHeight: bodyHeight, assetLoaded: assetLoaded
        )
        #expect(mode == expected)
    }
}

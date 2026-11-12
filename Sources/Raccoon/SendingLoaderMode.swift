import RaccoonDomain

/// What the Sending loader does in the Response body (surfaces.md §7). Pure: the viewer reads the
/// state, the clock, Reduce Motion, its own height and the asset, and draws what this says.
nonisolated enum SendingLoaderMode: Equatable, Sendable {
    case hidden
    /// The Fly pose with no playback (Reduce Motion).
    case still
    case play

    /// The loader's width and height, in points.
    static let side = 240.0

    /// 16 above, the loader, 8, one text line (16, computed, not measured), 16 below
    /// (design-system.md, Response viewer).
    static let neededBodyHeight = 16 + side + 8 + 16 + 16

    /// `bodyHeight` is the Response pane less the status line.
    static func of(
        _ state: ResponseState, now: ContinuousClock.Instant, reduceMotion: Bool, bodyHeight: Double, assetLoaded: Bool
    ) -> SendingLoaderMode {
        guard assetLoaded, state.showsSpinner(at: now), bodyHeight >= neededBodyHeight else { return .hidden }
        return reduceMotion ? .still : .play
    }
}

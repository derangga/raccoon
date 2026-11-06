/// When the Collection Export sheet's checks start fading in. Pure: the sheet passes the instants
/// its steps finished and the Reduce Motion setting.
public enum ExportStepReveal {
    /// The gap between two checks' starts.
    public static let stagger: Duration = .milliseconds(60)

    /// Check i starts at the later of its own finish and `stagger` after check i-1 started: a step
    /// that finishes late is shown when it finishes, and the stagger only spaces steps that finish
    /// together. Reduce Motion: every check starts at its finish.
    public static func starts(finishedAt: [Duration], reduceMotion: Bool) -> [Duration] {
        guard !reduceMotion else { return finishedAt }
        var starts: [Duration] = []
        for finished in finishedAt {
            starts.append(starts.last.map { max(finished, $0 + stagger) } ?? finished)
        }
        return starts
    }
}

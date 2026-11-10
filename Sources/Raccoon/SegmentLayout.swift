import CoreGraphics

/// The three looks of a SegmentedControl (design-system.md §6 Response viewer, Segmented control).
nonisolated enum SegmentStyle {
    /// A bordered box split by rules: the Inspector's pane switch.
    case boxed
    /// A tinted track with a thumb under the chosen title: Body | Headers | Timeline.
    case track
    /// Bare titles, an underline under the chosen one: Pretty | Raw.
    case underline
}

/// Where the segments of a SegmentedControl sit, from the width of each title alone.
nonisolated struct SegmentLayout {
    let style: SegmentStyle
    /// Each title with its count, in the semibold face, so choosing a segment never moves its neighbours.
    let contentWidths: [CGFloat]

    /// Space on each side of a title.
    private var padding: CGFloat {
        switch style {
        case .boxed: 10
        case .track: 12
        case .underline: 3
        }
    }

    /// Between two segments: the boxed rule, or the underline titles' air. The track's thumbs touch.
    private var gap: CGFloat {
        switch style {
        case .boxed: 1
        case .track: 0
        case .underline: 14
        }
    }

    /// From the control's edge to the first segment: the border, or the track's padding.
    private var inset: CGFloat {
        switch style {
        case .boxed: 1
        case .track: 2
        case .underline: 0
        }
    }

    /// The whole control.
    var width: CGFloat {
        contentWidths.reduce(0) { $0 + $1 + 2 * padding } + gap * CGFloat(max(contentWidths.count - 1, 0)) + 2 * inset
    }

    /// One frame per segment, in the control's flipped coordinates.
    func frames(height: CGFloat) -> [CGRect] {
        var x = inset
        return contentWidths.map { content in
            let width = content + 2 * padding
            defer { x += width + gap }
            return CGRect(x: x, y: inset, width: width, height: height - 2 * inset)
        }
    }

    /// The segment under `point`. Half of a gap belongs to each neighbour, and the whole height
    /// of the control counts, so no click lands on the border or the track's padding.
    func index(at point: CGPoint, height: CGFloat) -> Int? {
        guard (0..<height).contains(point.y) else { return nil }
        return frames(height: height).firstIndex { $0.insetBy(dx: -gap / 2, dy: 0).contains(CGPoint(x: point.x, y: $0.midY)) }
    }
}

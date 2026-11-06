import AppKit
import Testing

/// The button row after layout: each visible button at least as wide as it needs, the last one
/// on the trailing content edge (20 pt in), and each one 8 pt from the next.
@MainActor
func expectTrailingButtons(_ buttons: [NSButton], in view: NSView, sourceLocation: SourceLocation = #_sourceLocation) {
    view.layoutSubtreeIfNeeded()
    let frames = buttons.map { view.convert($0.bounds, from: $0) }
    for (button, frame) in zip(buttons, frames) {
        #expect(frame.width >= button.fittingSize.width - 0.5, "\(button.title) is \(frame.width) pt wide", sourceLocation: sourceLocation)
    }
    #expect(abs((frames.last?.maxX ?? 0) - (view.bounds.width - 20)) <= 1, "last button ends at \(frames.last?.maxX ?? 0)", sourceLocation: sourceLocation)
    for (left, right) in zip(frames, frames.dropFirst()) {
        #expect(abs(right.minX - left.maxX - 8) <= 1, "gap is \(right.minX - left.maxX)", sourceLocation: sourceLocation)
    }
}

import CoreGraphics
import Foundation

/// One number moving to a target on a critically damped spring: response 0.3 s, no overshoot
/// (surfaces.md §7, Segment indicator). A new target keeps the position and the speed it finds, so
/// turning round mid-slide has no jump and no restart. The clock is an argument.
nonisolated struct SlidingValue {
    /// Seconds to cover most of the way: the spring's natural period.
    static let response = 0.3
    private static let omega = 2 * Double.pi / response

    private(set) var target: CGFloat
    /// Position minus target, and its speed in points per second, at `since`.
    private var offset: CGFloat = 0
    private var speed: CGFloat = 0
    private var since: TimeInterval = 0

    init(at value: CGFloat) { target = value }

    private func elapsed(_ now: TimeInterval) -> Double { max(0, now - since) }

    func value(at now: TimeInterval) -> CGFloat {
        let t = elapsed(now), w = Self.omega
        return target + (offset + (speed + w * offset) * t) * exp(-w * t)
    }

    func velocity(at now: TimeInterval) -> CGFloat {
        let t = elapsed(now), w = Self.omega
        return (speed - w * (speed + w * offset) * t) * exp(-w * t)
    }

    /// Within a twentieth of a point of the target and slower than 5 pt/s: nothing left to see.
    func isSettled(at now: TimeInterval) -> Bool {
        abs(value(at: now) - target) < 0.05 && abs(velocity(at: now)) < 5
    }

    mutating func slide(to newTarget: CGFloat, at now: TimeInterval) {
        let position = value(at: now), carried = velocity(at: now)
        target = newTarget
        offset = position - newTarget
        speed = carried
        since = now
    }

    mutating func jump(to newTarget: CGFloat) {
        target = newTarget
        offset = 0
        speed = 0
    }
}

/// The thumb's or the underline's frame: x and width slide, y and height are the target's.
nonisolated struct IndicatorMotion {
    private var x: SlidingValue
    private var width: SlidingValue
    private(set) var target: CGRect

    init(frame: CGRect) {
        x = SlidingValue(at: frame.minX)
        width = SlidingValue(at: frame.width)
        target = frame
    }

    func frame(at now: TimeInterval) -> CGRect {
        CGRect(x: x.value(at: now), y: target.minY, width: width.value(at: now), height: target.height)
    }

    func isSettled(at now: TimeInterval) -> Bool { x.isSettled(at: now) && width.isSettled(at: now) }

    /// Moves toward `frame`: a slide, or in place at once. The frame it already has changes nothing.
    mutating func follow(_ frame: CGRect, animated: Bool, at now: TimeInterval) {
        guard frame != target else { return }
        target = frame
        if animated {
            x.slide(to: frame.minX, at: now)
            width.slide(to: frame.width, at: now)
        } else {
            x.jump(to: frame.minX)
            width.jump(to: frame.width)
        }
    }

    /// Ends a slide exactly on its target.
    mutating func settle() {
        x.jump(to: target.minX)
        width.jump(to: target.width)
    }
}

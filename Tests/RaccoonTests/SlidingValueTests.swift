import CoreGraphics
@testable import Raccoon
import Testing

/// The spring behind a segment indicator: critically damped, response 0.3 s (surfaces.md §7). Pure:
/// the clock is an argument, so every case is a table of times and positions.
struct SlidingValueTests {
    @Test func `a value at rest stays where it is`() {
        let value = SlidingValue(at: 10)
        #expect(value.value(at: 0) == 10 && value.value(at: 5) == 10)
        #expect(value.isSettled(at: 0))
    }

    @Test func `a slide starts at the old position`() {
        var value = SlidingValue(at: 0)
        value.slide(to: 100, at: 1)
        #expect(value.value(at: 1) == 0)
        #expect(!value.isSettled(at: 1))
    }

    @Test func `a 100 pt slide is 98.64 pt along after one response, and at its target once settled`() {
        var value = SlidingValue(at: 0)
        value.slide(to: 100, at: 1)
        #expect(abs(value.value(at: 1.3) - 98.64) < 0.01)
        #expect(abs(value.value(at: 3) - 100) < 0.001)
        #expect(!value.isSettled(at: 1.1))
        #expect(value.isSettled(at: 2))
    }

    @Test func `a slide from rest never passes its target and never goes back`() {
        var value = SlidingValue(at: 0)
        value.slide(to: 100, at: 0)
        var last: CGFloat = 0
        for step in 0...200 {
            let now = Double(step) * 0.01
            #expect(value.value(at: now) <= 100 && value.value(at: now) >= last)
            last = value.value(at: now)
        }
    }

    @Test func `a slide before time zero stays at its start`() {
        var value = SlidingValue(at: 0)
        value.slide(to: 100, at: 1)
        #expect(value.value(at: 0.5) == 0)
    }

    @Test func `turning round mid-slide keeps the position and the speed, then settles on the new target`() {
        var value = SlidingValue(at: 0)
        value.slide(to: 100, at: 0)
        let position = value.value(at: 0.1)
        let speed = value.velocity(at: 0.1)
        #expect(abs(position - 61.894) < 0.001 && abs(speed - 540.173) < 0.001)

        value.slide(to: 20, at: 0.1)
        #expect(abs(value.value(at: 0.1) - position) < 1e-9)
        #expect(abs(value.velocity(at: 0.1) - speed) < 1e-9)
        #expect(abs(value.value(at: 4) - 20) < 0.001)
    }

    @Test func `jumping puts the value at the target at once`() {
        var value = SlidingValue(at: 0)
        value.slide(to: 100, at: 0)
        value.jump(to: 40)
        #expect(value.value(at: 0.05) == 40 && value.target == 40)
        #expect(value.isSettled(at: 0.05))
    }
}

/// The thumb's or underline's frame: x and width slide, y and height are the target's.
struct IndicatorMotionTests {
    let first = CGRect(x: 2, y: 2, width: 64, height: 24)
    let second = CGRect(x: 66, y: 2, width: 84, height: 24)

    @Test func `it starts settled on its first frame`() {
        let motion = IndicatorMotion(frame: first)
        #expect(motion.frame(at: 0) == first && motion.target == first)
        #expect(motion.isSettled(at: 0))
    }

    @Test func `a slide moves x and width together and leaves y and height alone`() {
        var motion = IndicatorMotion(frame: first)
        motion.follow(second, animated: true, at: 1)
        #expect(motion.frame(at: 1) == first)
        let part = motion.frame(at: 1.1)
        #expect(part.minX > 2 && part.minX < 66 && part.width > 64 && part.width < 84)
        #expect(part.minY == 2 && part.height == 24)
        let end = motion.frame(at: 3)
        #expect(abs(end.minX - 66) < 0.001 && abs(end.width - 84) < 0.001)
        #expect(!motion.isSettled(at: 1.1) && motion.isSettled(at: 3))
    }

    @Test func `not animated puts the frame in place at once`() {
        var motion = IndicatorMotion(frame: first)
        motion.follow(second, animated: false, at: 1)
        #expect(motion.frame(at: 1) == second && motion.isSettled(at: 1))
    }

    @Test func `following the frame it already has changes nothing`() {
        var motion = IndicatorMotion(frame: first)
        motion.follow(second, animated: true, at: 1)
        let part = motion.frame(at: 1.1)
        motion.follow(second, animated: true, at: 1.1)
        #expect(motion.frame(at: 1.1) == part)
    }
}

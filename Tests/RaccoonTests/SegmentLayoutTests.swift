import AppKit
@testable import Raccoon
import Testing

/// Where the segments of a SegmentedControl sit, from the width of each title alone (design-system.md §6
/// Response viewer, Segmented control). Pure: no view, no theme.
struct SegmentLayoutTests {
    @Test func `boxed segments are the title plus 10 pt a side, split by a 1 pt rule inside a 1 pt border`() {
        let layout = SegmentLayout(style: .boxed, contentWidths: [40, 60])
        #expect(layout.frames(height: 24) == [CGRect(x: 1, y: 1, width: 60, height: 22), CGRect(x: 62, y: 1, width: 80, height: 22)])
        #expect(layout.width == 143)
    }

    @Test func `track segments are the title plus 12 pt a side, touching, inside 2 pt of padding`() {
        let layout = SegmentLayout(style: .track, contentWidths: [40, 60, 50])
        #expect(layout.frames(height: 28) == [
            CGRect(x: 2, y: 2, width: 64, height: 24),
            CGRect(x: 66, y: 2, width: 84, height: 24),
            CGRect(x: 150, y: 2, width: 74, height: 24),
        ])
        #expect(layout.width == 226)
    }

    @Test func `underline segments are the title plus 3 pt a side, 14 pt apart, as tall as the row`() {
        let layout = SegmentLayout(style: .underline, contentWidths: [40, 30])
        #expect(layout.frames(height: 38) == [CGRect(x: 0, y: 0, width: 46, height: 38), CGRect(x: 60, y: 0, width: 36, height: 38)])
        #expect(layout.width == 96)
    }

    @Test func `no segments leave only the inset`() {
        #expect(SegmentLayout(style: .track, contentWidths: []).width == 4)
        #expect(SegmentLayout(style: .underline, contentWidths: []).width == 0)
    }

    @Test func `a point picks the segment under it, the track's padding strip included`() {
        let layout = SegmentLayout(style: .track, contentWidths: [40, 60, 50])
        #expect(layout.index(at: CGPoint(x: 10, y: 14), height: 28) == 0)
        #expect(layout.index(at: CGPoint(x: 66, y: 14), height: 28) == 1)
        #expect(layout.index(at: CGPoint(x: 223, y: 14), height: 28) == 2)
        #expect(layout.index(at: CGPoint(x: 10, y: 1), height: 28) == 0)
        #expect(layout.index(at: CGPoint(x: 10, y: 27), height: 28) == 0)
    }

    @Test func `a point outside every segment picks none`() {
        let layout = SegmentLayout(style: .track, contentWidths: [40, 60, 50])
        #expect(layout.index(at: CGPoint(x: 1, y: 14), height: 28) == nil)
        #expect(layout.index(at: CGPoint(x: 224, y: 14), height: 28) == nil)
        #expect(layout.index(at: CGPoint(x: 10, y: 28), height: 28) == nil)
        #expect(layout.index(at: CGPoint(x: 10, y: -1), height: 28) == nil)
    }

    @Test func `the gap between two underline titles belongs half to each`() {
        let layout = SegmentLayout(style: .underline, contentWidths: [40, 30])
        #expect(layout.index(at: CGPoint(x: 50, y: 19), height: 38) == 0)
        #expect(layout.index(at: CGPoint(x: 52.9, y: 19), height: 38) == 0)
        #expect(layout.index(at: CGPoint(x: 53, y: 19), height: 38) == 1)
        #expect(layout.index(at: CGPoint(x: 56, y: 19), height: 38) == 1)
    }

    @Test func `the boxed rule belongs half to each neighbour`() {
        let layout = SegmentLayout(style: .boxed, contentWidths: [40, 60])
        #expect(layout.index(at: CGPoint(x: 61.2, y: 12), height: 24) == 0)
        #expect(layout.index(at: CGPoint(x: 61.8, y: 12), height: 24) == 1)
    }
}

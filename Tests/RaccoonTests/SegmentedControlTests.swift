import AppKit
@testable import Raccoon
import Testing

/// The control's own state: counts, and the height each style asks its row for.
@MainActor
struct SegmentedControlTests {
    let theme = ThemeEnvironment(catalog: ThemeCatalog.load(), isDark: false)

    @Test func `a count is part of its segment's label, and none leaves the title alone`() {
        let control = SegmentedControl(labels: ["Body", "Headers", "Timeline"], style: .track, theme: theme)
        control.setCount(11, forSegment: 1)
        #expect(control.label(forSegment: 1) == "Headers 11")
        #expect(control.label(forSegment: 0) == "Body")
        control.setCount(0, forSegment: 1)
        #expect(control.label(forSegment: 1) == "Headers 0")
        control.setCount(nil, forSegment: 1)
        #expect(control.label(forSegment: 1) == "Headers")
    }

    @Test func `a count for a segment that is not there is ignored`() {
        let control = SegmentedControl(labels: ["Pretty", "Raw"], style: .underline, theme: theme)
        control.setCount(3, forSegment: 2)
        control.setCount(3, forSegment: -1)
        #expect(control.label(forSegment: 0) == "Pretty" && control.label(forSegment: 1) == "Raw")
    }

    @Test func `the accessibility value names the selected segment with its count`() {
        let control = SegmentedControl(labels: ["Body", "Headers"], style: .track, theme: theme)
        control.setCount(11, forSegment: 1)
        control.selectedSegment = 1
        #expect(control.accessibilityValue() as? String == "Headers 11")
    }

    @Test func `a track is 28 pt high, boxed 24, and an underline takes the height of its row`() {
        #expect(SegmentedControl(labels: ["A"], style: .track, theme: theme).intrinsicContentSize.height == 28)
        #expect(SegmentedControl(labels: ["A"], theme: theme).intrinsicContentSize.height == 24)
        #expect(SegmentedControl(labels: ["A"], style: .underline, theme: theme).intrinsicContentSize.height == NSView.noIntrinsicMetric)
    }
}

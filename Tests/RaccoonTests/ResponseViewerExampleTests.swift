import AppKit
import Foundation
@testable import Raccoon
import RaccoonDomain
import RaccoonTesting
import Testing

/// The Response viewer showing an Example, and its Clear Response button (design-system.md §6 Response viewer).
@MainActor
struct ResponseViewerExampleTests {
    let base = ResponseViewerTests()
    let example = Example(
        id: ExampleID(UUID()), name: "Card declined", status: 402,
        headers: [Row(name: "Content-Type", value: "application/json")], body: .text(#"{"a":1}"#))

    func settle() async {
        for _ in 0..<10 { await Task.yield() }
    }

    /// A Request Tab that received a live Response, then had `example` shown.
    func showing() async -> (TabModel, ResponseViewer) {
        let (model, _) = await base.received(base.response(Data("live".utf8)))
        model.tab.source = .request(RequestID(UUID()))
        model.show(example)
        await model.presenting?.value
        return (model, base.viewer(model))
    }

    @Test func `the status line reads the code, the reason and the Example's name, with no time or size`() async {
        let (_, viewer) = await showing()

        #expect(viewer.codeLabel.stringValue == "402" && viewer.reasonLabel.stringValue == "Payment Required")
        #expect(viewer.elapsedLabel.stringValue == "Card declined" && !viewer.elapsedLabel.isHidden)
        #expect(viewer.dot.isHidden && viewer.sizeLabel.isHidden)
    }

    @Test func `a live Response keeps its time and size, and the name's label is a time again`() async {
        let (model, _) = await base.received(base.response(Data("live".utf8)))
        let viewer = base.viewer(model)

        #expect(viewer.elapsedLabel.stringValue == "184 ms" && viewer.sizeLabel.stringValue == "4 B")
    }

    @Test func `the body is Pretty, with Raw and Headers as for a Response`() async {
        let (_, viewer) = await showing()

        #expect(viewer.textView.textStorage?.string == "{\n  \"a\": 1\n}")
        #expect(viewer.mode.isEnabled(forSegment: 0) && viewer.mode.selectedSegment == 0)
        #expect(viewer.section.label(forSegment: 1) == "Headers 1")
    }

    @Test func `there is no Timeline segment while an Example shows, and it comes back with a Response`() async {
        let (model, viewer) = await showing()
        #expect(viewer.section.segmentCount == 2)

        model.clearResponse()
        model.tab.response = .received(base.response(Data("live".utf8)))
        await settle()

        #expect(viewer.section.segmentCount == 3)
    }

    @Test func `an Example shown while the Timeline was open brings the Body back`() async {
        let (model, _) = await base.received(base.response(Data("live".utf8)))
        let viewer = base.viewer(model)
        viewer.section.selectedSegment = 2
        viewer.section.sendAction(viewer.section.action, to: viewer.section.target)
        #expect(viewer.section.selectedSegment == 2)

        model.show(example)
        await settle()

        #expect(viewer.section.selectedSegment == 0)
    }

    @Test func `Save as Example is off, since it is already saved`() async {
        let (_, viewer) = await showing()

        #expect(!viewer.exampleButton.isEnabled)
        #expect(viewer.exampleButton.toolTip == "Already saved")
    }

    @Test func `Clear Response comes last, 4 pt after Save as Example, with its shortcut in the tooltip`() async {
        let (_, viewer) = await showing()

        #expect(viewer.clearButton.isEnabled)
        #expect(viewer.clearButton.toolTip == "Clear Response (⌥⌘K)")
        #expect(viewer.clearButton.accessibilityLabel() == "Clear Response")
        #expect(viewer.clearButton.frame.minX - viewer.exampleButton.frame.maxX == 4)
        #expect(viewer.clearButton.frame.maxX == viewer.bodyToolbar.bounds.maxX - 12)
    }

    @Test func `a click goes up the responder chain to the app's Clear Response`() async {
        let (_, viewer) = await showing()

        #expect(viewer.clearButton.target == nil)
        #expect(viewer.clearButton.action == #selector(AppDelegate.clearResponse(_:)))
    }

    @Test func `Clear Response is on for a live Response, and off while a send is in flight`() async {
        let (model, _) = await base.received(base.response(Data("live".utf8)))
        let viewer = base.viewer(model)
        #expect(viewer.clearButton.isEnabled)

        model.send()
        model.show(example)
        // Drawn before the scripted send can land: it would replace the Example.
        viewer.render()

        #expect(viewer.elapsedLabel.stringValue == "Card declined")
        #expect(!viewer.clearButton.isEnabled)
    }
}

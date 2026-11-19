import AppKit
import Foundation
@testable import Raccoon
import RaccoonDomain
import RaccoonTesting
import Testing

/// The Body toolbar's Save as Example button and its note (design-system.md §6 Response viewer).
@MainActor
struct ResponseViewerSaveExampleTests {
    let base = ResponseViewerTests()
    /// A 1 × 1 PNG, so ImageIO decodes it.
    let png = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==")!

    /// A Tab on a Request, or a Draft, that has received a Response with `body`.
    func received(_ body: Data, headers: [Response.Header] = [], request: Bool = true) async -> (TabModel, ResponseViewer) {
        var response = base.response(body)
        response.headers = headers
        let (model, _) = await base.received(response)
        if request { model.tab.source = .request(RequestID(UUID())) }
        return (model, base.viewer(model))
    }

    func settle() async {
        for _ in 0..<10 { await Task.yield() }
    }

    @Test func `on a Request Tab it is enabled, with its shortcut in the tooltip and a plain accessibility label`() async {
        let (_, viewer) = await received(Data("hi".utf8))

        #expect(viewer.exampleButton.isEnabled)
        #expect(viewer.exampleButton.toolTip == "Save as Example (⌥⌘E)")
        #expect(viewer.exampleButton.accessibilityLabel() == "Save as Example")
    }

    @Test func `on a Draft it is disabled and says to save the Request first`() async {
        let (_, viewer) = await received(Data("hi".utf8), request: false)

        #expect(!viewer.exampleButton.isEnabled)
        #expect(viewer.exampleButton.toolTip == "Save the Request first")
    }

    @Test func `a Draft that is saved gets the button back, with its own tooltip`() async {
        let (model, viewer) = await received(Data("hi".utf8), request: false)

        model.tab.source = .request(RequestID(UUID()))
        await settle()

        #expect(viewer.exampleButton.isEnabled)
        #expect(viewer.exampleButton.toolTip == "Save as Example (⌥⌘E)")
    }

    @Test func `an image keeps it enabled while Search and Copy are off`() async {
        let (_, viewer) = await received(png, headers: [.init(name: "Content-Type", value: "image/png")])

        #expect(!viewer.searchButton.isEnabled && !viewer.copyButton.isEnabled)
        #expect(viewer.exampleButton.isEnabled)
    }

    @Test func `a binary body in the Hex view keeps it enabled`() async {
        let (_, viewer) = await received(Data([0xFF, 0xFE, 0x00, 0x81]))

        #expect(viewer.exampleButton.isEnabled)
    }

    @Test func `it comes last in the toolbar, 4 pt after Copy, which is 4 pt after Search`() async {
        let (_, viewer) = await received(Data("hi".utf8))

        #expect(viewer.copyButton.frame.minX - viewer.searchButton.frame.maxX == 4)
        #expect(viewer.exampleButton.frame.minX - viewer.copyButton.frame.maxX == 4)
        #expect(viewer.exampleButton.frame.maxX == viewer.bodyToolbar.bounds.maxX - 12)
        #expect(viewer.exampleButton.frame.size == NSSize(width: 24, height: 24))
    }

    @Test func `a click goes up the responder chain to the app's Save as Example`() async {
        let (_, viewer) = await received(Data("hi".utf8))

        #expect(viewer.exampleButton.target == nil)
        #expect(viewer.exampleButton.action == #selector(AppDelegate.saveAsExample(_:)))
    }

    @Test func `a failed save shows its reason as the note in the error colour, until it is cleared`() async {
        let (model, viewer) = await received(Data("hi".utf8))
        #expect(viewer.exampleNote.isHidden)

        model.exampleNote = "Couldn't save the Example: the disk is full."
        await settle()
        viewer.layoutSubtreeIfNeeded()

        #expect(!viewer.exampleNote.isHidden)
        #expect(viewer.exampleNote.stringValue == "Couldn't save the Example: the disk is full.")
        #expect(viewer.exampleNote.textColor == base.theme.color(.error))
        #expect(viewer.exampleNote.toolTip == "Couldn't save the Example: the disk is full.")

        model.exampleNote = nil
        await settle()

        #expect(viewer.exampleNote.isHidden)
    }

    @Test func `the note truncates before the buttons give way`() async {
        let (model, viewer) = await received(Data("hi".utf8))
        model.exampleNote = "Couldn't save the Example: " + String(repeating: "a very long reason ", count: 40)
        await settle()
        viewer.layoutSubtreeIfNeeded()

        #expect(viewer.exampleNote.frame.maxX <= viewer.searchButton.frame.minX)
        #expect(viewer.exampleButton.frame.maxX == viewer.bodyToolbar.bounds.maxX - 12)
    }

    func showHeaders(_ viewer: ResponseViewer) {
        viewer.section.selectedSegment = 1
        viewer.section.sendAction(viewer.section.action, to: viewer.section.target)
    }

    /// A viewer on a window's Request Tab that holds a Response, and an app over that window; the file is garbage when `broken`.
    func app(broken: Bool) async throws -> (AppDelegate, TabModel, ResponseViewer) {
        let saving = SaveAsExampleTests()
        let (window, tab) = try saving.received()
        if broken { try Data("not json".utf8).write(to: saving.base.file) }
        let delegate = AppDelegate()
        delegate.windowModel = window
        return (delegate, tab, base.viewer(tab))
    }

    @Test func `a failure from the Headers section switches to Body, so the toolbar and the note show`() async throws {
        let (delegate, _, viewer) = try await app(broken: true)
        showHeaders(viewer)
        #expect(viewer.section.selectedSegment == 1 && viewer.bodyToolbar.isHidden)

        delegate.saveAsExample(nil)
        await settle()

        #expect(viewer.section.selectedSegment == 0)
        #expect(!viewer.bodyToolbar.isHidden)
        #expect(!viewer.exampleNote.isHidden)
        #expect(viewer.exampleNote.stringValue.hasPrefix("Couldn't save the Example: "))
    }

    @Test func `a second failure from the Headers section switches again, though the note reads the same`() async throws {
        let (delegate, _, viewer) = try await app(broken: true)
        delegate.saveAsExample(nil)
        await settle()
        showHeaders(viewer)

        delegate.saveAsExample(nil)
        await settle()

        #expect(viewer.section.selectedSegment == 0)
    }

    @Test func `a save that lands from the Headers section leaves it on Headers`() async throws {
        let (delegate, _, viewer) = try await app(broken: false)
        showHeaders(viewer)

        delegate.saveAsExample(nil)
        await settle()

        #expect(viewer.section.selectedSegment == 1)
        #expect(!viewer.headerList.isHidden)
        #expect(viewer.exampleNote.isHidden)
    }

    @Test func `a failure on an empty body shows the note in the void, in the error colour, until it is cleared`() async {
        let (model, viewer) = await received(Data())
        #expect(viewer.voidText.stringValue == "Empty body." && viewer.exampleVoidNote.isHidden)

        model.exampleNote = "Couldn't save the Example: the disk is full."
        await settle()

        #expect(viewer.bodyToolbar.isHidden)
        #expect(viewer.voidText.stringValue == "Empty body.")
        #expect(!viewer.exampleVoidNote.isHidden)
        #expect(viewer.exampleVoidNote.stringValue == "Couldn't save the Example: the disk is full.")
        #expect(viewer.exampleVoidNote.textColor == base.theme.color(.error))

        model.exampleNote = nil
        await settle()

        #expect(viewer.exampleVoidNote.isHidden)
    }

    @Test func `a failure while the toolbar shows keeps the void note out of the way`() async {
        let (model, viewer) = await received(Data("hi".utf8))

        model.exampleNote = "Couldn't save the Example: the disk is full."
        await settle()

        #expect(viewer.exampleVoidNote.isHidden && !viewer.exampleNote.isHidden)
    }
}

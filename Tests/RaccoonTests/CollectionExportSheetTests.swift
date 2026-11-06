import AppKit
import Foundation
@testable import Raccoon
import RaccoonData
import RaccoonDomain
import RaccoonTesting
import Testing

/// The Collection Export sheet over a hand-fed step stream, with a recording FileWriting and a
/// save panel that answers what the test says.
@MainActor
struct CollectionExportSheetTests {
    let target = URL(filePath: "/tmp/raccoon-export/Sociolla.postman_collection.json")
    let other = URL(filePath: "/tmp/raccoon-export/Other.postman_collection.json")
    let model = CollectionExportModel(name: "Sociolla", folder: "~/Raccoon")

    func plan(
        requests: Int = 41, folders: Int = 11, findings: [CredentialFinding] = [], skipped: [ExportSkip] = [], dirty: [String] = []
    ) -> ExportPlan {
        ExportPlan(
            collection: ExportCollection(name: "Sociolla", nodes: []), requests: requests, folders: folders, findings: findings,
            skipped: skipped, dirtyRequests: dirty, data: Data("the file".utf8)
        )
    }

    func steps(_ plan: ExportPlan) -> AsyncStream<ExportStep> {
        AsyncStream { continuation in
            continuation.yield(.read(count: plan.requests))
            continuation.yield(.formatted)
            continuation.yield(.scanned(plan))
            continuation.finish()
        }
    }

    /// The sheet and what it was given; `asked` records the names the save panel was asked for.
    @MainActor final class Harness {
        let sheet: CollectionExportSheet
        /// The sheet's own window, so the save panel has one to attach to.
        let window: NSWindow
        let files: RecordingFileWriting
        var asked: [String] = []
        var exported = 0

        init(model: CollectionExportModel, steps: AsyncStream<ExportStep>, files: RecordingFileWriting, answers: [URL?], reduceMotion: Bool) {
            self.files = files
            var answers = answers
            var box: Harness?
            let sheet = CollectionExportSheet(
                model: model, steps: steps, writer: files,
                choose: { _, name in
                    box?.asked.append(name)
                    return answers.isEmpty ? nil : answers.removeFirst()
                },
                reduceMotion: { reduceMotion }
            )
            sheet.onExported = { box?.exported += 1 }
            self.sheet = sheet
            window = sheetPanel(sheet, focus: sheet.exportButton)
            box = self
            _ = sheet.view
        }
    }

    func harness(
        _ plan: ExportPlan? = nil, files: RecordingFileWriting = RecordingFileWriting(), answers: [URL?] = [], reduceMotion: Bool = true
    ) -> Harness {
        let plan = plan ?? self.plan()
        return Harness(model: model, steps: steps(plan), files: files, answers: answers, reduceMotion: reduceMotion)
    }

    func texts(_ sheet: CollectionExportSheet) -> [String] { sheet.stepRows.map(\.label.stringValue) }

    @Test func `the buttons sit on the trailing edge, before and after the steps`() async {
        let h = harness()
        expectTrailingButtons([h.sheet.cancelButton, h.sheet.exportButton], in: h.sheet.view)
        await h.sheet.run()
        expectTrailingButtons([h.sheet.cancelButton, h.sheet.exportButton], in: h.sheet.view)
    }

    @Test func `before the first step: the title, three undrawn rows, no counts, Export… disabled`() {
        let h = harness()
        #expect(h.sheet.titleLabel.stringValue == "Export “Sociolla”")
        #expect(h.sheet.stepRows.map(\.alphaValue) == [0, 0, 0])
        #expect(h.sheet.details.isHidden)
        #expect(!h.sheet.exportButton.isEnabled)
        #expect(h.sheet.exportButton.title == "Export…")
        #expect(h.sheet.cancelButton.title == "Cancel")
    }

    @Test func `the steps, then the counts, with Export… enabled in the same frame as the third check`() async {
        let h = harness(plan(findings: [CredentialFinding(request: "Login", place: .bearerToken)]))
        await h.sheet.run()

        #expect(texts(h.sheet) == ["Read 41 Requests from ~/Raccoon", "Formatted as Collection Format v2.1", "Scanned for credentials"])
        #expect(h.sheet.stepRows.map(\.alphaValue) == [1, 1, 1])
        #expect(!h.sheet.details.isHidden)
        #expect(h.sheet.countsLabel.stringValue == "41 Requests · 11 Folders")
        #expect(h.sheet.exportButton.isEnabled)
    }

    @Test func `Reduce Motion: each row is drawn at its finish, with no fade`() async {
        let (stream, feed) = AsyncStream<ExportStep>.makeStream()
        let h = Harness(model: model, steps: stream, files: RecordingFileWriting(), answers: [], reduceMotion: true)
        let running = Task { await h.sheet.run() }

        feed.yield(.read(count: 3))
        for _ in 0..<20 { await Task.yield() }
        #expect(h.sheet.stepRows.map(\.alphaValue) == [1, 0, 0])
        #expect(h.sheet.details.isHidden)

        feed.yield(.formatted)
        for _ in 0..<20 { await Task.yield() }
        #expect(h.sheet.stepRows.map(\.alphaValue) == [1, 1, 0])

        feed.yield(.scanned(plan()))
        feed.finish()
        await running.value
        #expect(h.sheet.stepRows.map(\.alphaValue) == [1, 1, 1])
        #expect(!h.sheet.details.isHidden)
    }

    @Test func `with motion, steps finishing together are still all drawn, Export… last`() async {
        let h = harness(reduceMotion: false)
        await h.sheet.run()
        #expect(texts(h.sheet).count == 3)
        #expect(!h.sheet.details.isHidden)
        #expect(h.sheet.exportButton.isEnabled)
    }

    @Test func `credentials, skipped files and Dirty Requests sit under the counts, in that order`() async {
        let h = harness(plan(
            requests: 1, folders: 1, findings: [CredentialFinding(request: "Login", place: .bearerToken)],
            skipped: [ExportSkip(path: "Sociolla/Broken.json", reason: "x")], dirty: ["Login"]
        ))
        await h.sheet.run()

        #expect(h.sheet.countsLabel.stringValue == "1 Request · 1 Folder")
        #expect(h.sheet.noticeViews.map(\.headline.stringValue) == [
            "1 credential in plain text", "1 file is not exported", "1 Request has edits in a Tab. Export uses what is saved.",
        ])
        #expect(h.sheet.noticeViews[0].names.stringValue == "Login")
        #expect(h.sheet.noticeViews[1].names.stringValue == "Broken.json")
        #expect(h.sheet.noticeViews[1].names.toolTip == "Broken.json: x")
    }

    @Test func `break-ui: a warning naming 40 Requests stays one line, then and N more`() async throws {
        let findings = (1...40).map { CredentialFinding(request: "Request number \($0)", place: .header("authorization")) }
        let h = harness(plan(findings: findings))
        await h.sheet.run()
        h.sheet.view.layoutSubtreeIfNeeded()

        let names = try #require(h.sheet.noticeViews.first?.names)
        let text = names.stringValue
        #expect(text.hasPrefix("Request number 1 · Request number 2"))
        #expect(text.range(of: #" and \d+ more$"#, options: .regularExpression) != nil)
        #expect(!text.contains("\n"))
        #expect(names.maximumNumberOfLines == 1)
        #expect(NSAttributedString(string: text, attributes: [.font: names.font!]).size().width <= CollectionExportSheet.bodyWidth - 22)
        #expect(names.toolTip?.contains("Request number 40") == true)
    }

    @Test func `a second press while the save panel is being asked for does nothing`() async {
        let h = harness(answers: [target, target])
        await h.sheet.run()

        h.sheet.exportButton.performClick(nil)
        // At once, before the task the press started has run.
        #expect(!h.sheet.exportButton.isEnabled)
        h.sheet.exportButton.performClick(nil)
        for _ in 0..<50 { await Task.yield() }

        #expect(h.asked.count == 1)
    }

    @Test func `Cancel closes the sheet and writes nothing, nor opens the save panel`() async {
        let h = harness(answers: [target])
        await h.sheet.run()
        h.sheet.cancelButton.performClick(nil)
        for _ in 0..<20 { await Task.yield() }
        #expect(h.files.writes.isEmpty)
        #expect(h.asked.isEmpty)
        #expect(h.exported == 0)
    }

    @Test func `Cancel in the save panel returns to the sheet, nothing written`() async {
        let h = harness(answers: [nil])
        await h.sheet.run()
        await h.sheet.export()

        #expect(h.asked == ["Sociolla.postman_collection.json"])
        #expect(h.files.writes.isEmpty)
        #expect(h.exported == 0)
        #expect(h.sheet.failureLabel.isHidden)
        #expect(h.sheet.exportButton.isEnabled)
    }

    @Test func `Export… writes the plan's bytes where the panel said, and closes`() async {
        let h = harness(answers: [target])
        await h.sheet.run()
        await h.sheet.export()

        #expect(h.files.writes.map(\.url) == [target])
        #expect(h.files.writes.map(\.data) == [Data("the file".utf8)])
        #expect(h.exported == 1)
    }

    @Test func `a target that is not writable: the reason on the sheet, nothing written, and another place still works`() async {
        let files = RecordingFileWriting(failing: [target: .unwritable(path: target.path, reason: "The folder “raccoon-export” is not writable.")])
        let h = harness(files: files, answers: [target, other])
        await h.sheet.run()
        await h.sheet.export()

        #expect(files.writes.isEmpty)
        #expect(h.exported == 0)
        #expect(!h.sheet.failureLabel.isHidden)
        #expect(h.sheet.failureLabel.stringValue == "Not exported. The folder “raccoon-export” is not writable.")
        #expect(h.sheet.exportButton.isEnabled)

        await h.sheet.export()
        #expect(files.writes.map(\.url) == [other])
        #expect(h.exported == 1)
    }

    @Test func `Cancel ends the sheet on its parent`() async {
        let h = harness()
        let parent = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 400), styleMask: [.titled], backing: .buffered, defer: false)
        parent.beginSheet(h.window, completionHandler: nil)
        #expect(parent.attachedSheet === h.window)

        h.sheet.cancelButton.performClick(nil)
        for _ in 0..<50 { await Task.yield() }
        #expect(parent.attachedSheet == nil)
    }

    @Test func `the sheet is 440 pt wide with 22 pt rows, and only grows when the counts arrive`() async {
        let h = harness(plan(findings: [CredentialFinding(request: "Login", place: .bearerToken)]))
        h.sheet.view.layoutSubtreeIfNeeded()
        let before = h.sheet.view.fittingSize
        #expect(before.width == 440)
        #expect(h.sheet.stepRows.map(\.frame.height) == [22, 22, 22])
        let rows = h.sheet.stepRows.map(\.frame.minY)

        await h.sheet.run()
        h.sheet.view.layoutSubtreeIfNeeded()
        #expect(h.sheet.view.fittingSize.width == 440)
        #expect(h.sheet.view.fittingSize.height > before.height)
        // The rows did not move: only what is below them was added.
        #expect(h.sheet.stepRows.map(\.frame.minY) == rows)
    }
}

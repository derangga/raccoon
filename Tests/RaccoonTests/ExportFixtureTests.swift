import AppKit
import Foundation
@testable import Raccoon
import RaccoonData
import RaccoonDomain
import RaccoonTesting
import Testing

/// manual-tests/postman-export/datafolder, the Data Folder the manual scenarios run on: what the
/// sheet shows for each of its Collections is what the scenarios say.
@MainActor
struct ExportFixtureTests {
    let base = PrepareExportTests()

    nonisolated static let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appending(path: "manual-tests/postman-export/datafolder")

    /// The sheet's text for one Collection, after every step, in a window of the fixture's copy.
    func shown(_ collection: String) async throws -> (steps: [String], counts: String, notices: [[String]]) {
        try FileManager.default.createDirectory(at: base.temp, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: Self.fixture, to: base.root)
        let window = base.makeWindow()
        let model = CollectionExportModel(name: collection, folder: "/tmp/raccoon-export")
        let sheet = CollectionExportSheet(
            model: model, steps: try #require(window.prepareExport(collection, id: base.exportID)), writer: RecordingFileWriting(),
            choose: { _, _ in nil }, reduceMotion: { true }
        )
        _ = sheet.view
        await sheet.run()
        return (
            sheet.stepRows.map(\.label.stringValue), sheet.countsLabel.stringValue,
            sheet.noticeViews.map { [$0.headline.stringValue, $0.names.stringValue] }
        )
    }

    static let steps = ["Read %d Requests from /tmp/raccoon-export", "Formatted as Collection Format v2.1", "Scanned for credentials"]

    @Test func `Payments API: 7 Requests, 3 Folders, 5 credentials in 4 Requests, and Broken.json left out`() async throws {
        let s = try await shown("Payments API")
        #expect(s.steps == [String(format: Self.steps[0], 7), Self.steps[1], Self.steps[2]])
        #expect(s.counts == "7 Requests · 3 Folders")
        #expect(s.notices == [
            ["5 credentials in plain text", "Old refund · Create refund · Capture charge · Create charge"],
            ["1 file is not exported", "Broken.json"],
        ])
    }

    @Test func `Clean API: 2 Requests, no warning`() async throws {
        let s = try await shown("Clean API")
        #expect(s.counts == "2 Requests · 0 Folders")
        #expect(s.notices.isEmpty)
    }

    @Test func `Big Collection: 40 credentials naming 40 Requests, on one line`() async throws {
        let s = try await shown("Big Collection")
        #expect(s.counts == "40 Requests · 0 Folders")
        #expect(s.notices.count == 1)
        #expect(s.notices[0][0] == "40 credentials in plain text")
        #expect(s.notices[0][1].hasPrefix("Request number 1 · Request number 2"))
        #expect(s.notices[0][1].hasSuffix(" more"))
    }
}

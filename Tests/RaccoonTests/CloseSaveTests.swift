import AppKit
@testable import Raccoon
import RaccoonData
import RaccoonDomain
import RaccoonTesting
import Testing

/// Save in the close prompt, over a live store in a temp dir.
@MainActor
struct CloseSaveTests {
    let base = SaveRequestTests()

    func closer(_ window: WindowModel, sheet: SaveDraftAnswer? = nil) -> TabCloser {
        TabCloser(window: window, saver: DraftSaver(window: window, ask: { _, _, reply in reply(sheet) }, focusURL: {}),
                  memory: CloseMemory(), ask: { _, reply in reply(.save) })
    }

    @Test func `Save on a Dirty Request writes the file and closes the Tab`() throws {
        let (window, tab) = try base.openEdited()

        closer(window).close(tab)

        #expect(!window.tabs.contains { $0 === tab })
        #expect(try RequestFile.decode(Data(contentsOf: base.file)).definition == tab.tab.definition)
    }

    @Test func `a Save that fails keeps the Tab open, Dirty, with Not saved`() throws {
        let (window, tab) = try base.openEdited()
        let folder = base.file.deletingLastPathComponent()
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: folder.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: folder.path) }

        closer(window).close(tab)

        #expect(window.tabs.contains { $0 === tab })
        #expect(tab.tab.isDirty)
        guard case .notSaved = tab.notice else { Issue.record("no Not saved"); return }
    }

    @Test func `Save on a Draft opens the sheet; Cancel there keeps the Tab`() throws {
        let (window, _) = try base.openEdited()
        let draft = window.tabs[0]
        draft.typeInURLBar("https://api.example.com/x")

        closer(window, sheet: nil).close(draft)

        #expect(window.tabs.contains { $0 === draft })
        #expect(draft.tab.source == .draft)
    }

    @Test func `Save on a Draft saves it where the sheet says, then closes`() throws {
        let (window, _) = try base.openEdited()
        let draft = window.tabs[0]
        draft.typeInURLBar("https://api.example.com/x")

        closer(window, sheet: SaveDraftAnswer(name: "Ping", location: .folder("Payments API"))).close(draft)

        #expect(!window.tabs.contains { $0 === draft })
        #expect(FileManager.default.fileExists(atPath: base.root.appending(path: "Payments API/Ping.json").path))
    }
}

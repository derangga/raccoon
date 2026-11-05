import Foundation
@testable import Raccoon
import RaccoonDomain
import Testing

/// The Leave sheet's sentence and what each answer does (workspaces.md §switchWorkspace).
@MainActor
struct LeaveConfirmTests {
    let base = SaveRequestTests()

    /// Answers the sheet in order; the Save Request sheet answers `sheet` every time.
    final class Script {
        var choices: [LeaveChoice]
        var counts: [Int] = []
        var sheets = 0
        init(_ choices: LeaveChoice...) { self.choices = choices }
    }

    func confirmer(_ window: WindowModel, _ script: Script, sheet: SaveDraftAnswer?) -> LeaveConfirmer {
        let saver = DraftSaver(window: window, ask: { _, _, reply in
            script.sheets += 1
            reply(sheet)
        }, focusURL: {})
        return LeaveConfirmer(saver: saver) { count, reply in
            script.counts.append(count)
            reply(script.choices.removeFirst())
        }
    }

    @Test(arguments: [
        (1, "1 Tab has unsaved changes. Save it before switching Workspaces, or it will be lost.", "Save"),
        (2, "2 Tabs have unsaved changes. Save them before switching Workspaces, or they will be lost.", "Save All"),
        (5, "5 Tabs have unsaved changes. Save them before switching Workspaces, or they will be lost.", "Save All"),
    ] as [(Int, String, String)])
    func `the sentence and the default button follow the count`(count: Int, message: String, button: String) {
        #expect(LeaveConfirm.message(count: count) == message)
        #expect(LeaveConfirm.saveTitle(count: count) == button)
    }

    @Test func `Cancel says stay and saves nothing`() async throws {
        let (window, dirty) = try base.openEdited()
        let script = Script(.cancel)

        let leave = await confirmer(window, script, sheet: nil).confirm([dirty])

        #expect(!leave && script.counts == [1] && dirty.tab.isDirty)
    }

    @Test func `Don't Save says go and leaves the Tabs for the window to discard`() async throws {
        let (window, dirty) = try base.openEdited()
        let script = Script(.dontSave)

        let leave = await confirmer(window, script, sheet: nil).confirm([dirty])

        #expect(leave && dirty.tab.isDirty && script.sheets == 0)
    }

    @Test func `Save All writes a Dirty Request and asks where for a Draft, then says go`() async throws {
        let (window, dirty) = try base.openEdited()
        let draft = window.tabs[0]
        draft.typeInURLBar("https://api.example.com/x")
        let script = Script(.saveAll)

        let leave = await confirmer(window, script, sheet: SaveDraftAnswer(name: "Ping", location: .folder("Payments API")))
            .confirm([dirty, draft])

        #expect(leave && script.counts == [2] && script.sheets == 1)
        #expect(!dirty.tab.isDirty && draft.tab.source != .draft)
    }

    @Test func `Save All stops at a Draft whose Save Request sheet was cancelled, and says stay`() async throws {
        let (window, dirty) = try base.openEdited()
        let draft = window.tabs[0]
        draft.typeInURLBar("https://api.example.com/x")
        let script = Script(.saveAll)

        // The Draft first: the Request after it is never reached.
        let leave = await confirmer(window, script, sheet: nil).confirm([draft, dirty])

        #expect(!leave && script.sheets == 1)
        #expect(draft.tab.source == .draft && dirty.tab.isDirty)
    }
}

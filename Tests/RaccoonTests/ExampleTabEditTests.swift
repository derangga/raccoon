import Foundation
@testable import Raccoon
import RaccoonDomain
import RaccoonTesting
import Testing

/// The edit methods of an Example Tab: one undo step each, clamped by the Example, Dirty by content
/// against the baseline, and nothing on a Draft or a Request Tab.
@MainActor
struct ExampleTabEditTests {
    let request = RequestID(UUID())
    let original = Example(
        id: ExampleID(UUID()), name: "ok", status: 200, headers: [Row(name: "Content-Type", value: "application/json")],
        body: .text("{}"), delayMilliseconds: 10)

    func model(files: [String: Data] = [:], baseline: Bool = true) -> TabModel {
        let model = TabModel(
            transport: ScriptedTransport(.failure(.timedOut(seconds: 60))), secrets: InMemorySecretStore(),
            files: DictionaryFileReading(files), instants: FixedInstantSource(.now), clipboard: RecordingClipboardWriter())
        model.tab = Tab(id: TabID(UUID()), source: .example(request, original.id), content: .example(original),
                        baseline: baseline ? .example(original) : nil)
        return model
    }

    /// A manager that closes a step only when told, so each edit is one `undo()`.
    func manager() -> UndoManager {
        let manager = UndoManager()
        manager.groupsByEvent = false
        return manager
    }

    func step(_ manager: UndoManager, _ edit: () -> Void) {
        manager.beginUndoGrouping()
        edit()
        manager.endUndoGrouping()
    }

    // MARK: Edits and Dirty

    @Test func `each edit method writes its field and leaves the rest`() {
        let model = model()
        model.setExampleName("created")
        model.setExampleStatus(201)
        model.setExampleDelay(250)
        model.setExampleHeaders([Row(name: "X-A", value: "1")])
        model.setExampleBody(.bytes(Data([1, 2])))
        #expect(model.tab.example == Example(
            id: original.id, name: "created", status: 201, headers: [Row(name: "X-A", value: "1")],
            body: .bytes(Data([1, 2])), delayMilliseconds: 250))
    }

    @Test func `Dirty comes from the content against the baseline, with no flag`() {
        let model = model()
        #expect(!model.tab.isDirty)
        model.setExampleName("changed")
        #expect(model.tab.isDirty)
        model.setExampleName("ok")
        #expect(!model.tab.isDirty)
    }

    @Test(arguments: [(700, 599), (600, 599), (599, 599), (100, 100), (99, 100), (20, 100), (-5, 100), (404, 404)])
    func `a status is clamped to 100 through 599`(typed: Int, stored: Int) {
        let model = model()
        model.setExampleStatus(typed)
        #expect(model.tab.example?.status == stored)
    }

    @Test(arguments: [(-1, 0), (0, 0), (60_000, 60_000), (60_001, 60_000), (999_999, 60_000), (1_500, 1_500)])
    func `a delay is clamped to 0 through 60000`(typed: Int, stored: Int) {
        let model = model()
        model.setExampleDelay(typed)
        #expect(model.tab.example?.delayMilliseconds == stored)
    }

    @Test func `an Example with no baseline is Dirty, as it is not on disk`() {
        #expect(model(baseline: false).tab.isDirty)
    }

    @Test(arguments: [DraftOrRequest.draft, .request])
    func `the edit methods do nothing on a Draft or a Request Tab`(kind: DraftOrRequest) {
        let model = model()
        model.tab = Tab(id: TabID(UUID()), source: kind == .draft ? .draft : .request(request), definition: .empty, baseline: .empty)
        let manager = manager()
        step(manager) {
            model.setExampleName("x", undo: manager)
            model.setExampleStatus(500, undo: manager)
            model.setExampleDelay(5, undo: manager)
            model.setExampleHeaders([Row(name: "a", value: "b")], undo: manager)
            model.setExampleBody(.text("x"), undo: manager)
        }
        #expect(model.tab.content == .request(.empty))
        #expect(manager.levelsOfUndo == 0)
    }

    @Test func `an Example edit never touches a definition`() {
        let model = model()
        model.setExampleName("renamed")
        #expect(model.tab.definition == .empty)
    }

    // MARK: Undo

    @Test(arguments: Edit.allCases)
    func `an edit is one undo step with an action name, and redo puts it back`(edit: Edit) {
        let model = model()
        let manager = manager()
        step(manager) { edit.apply(model, manager) }
        let edited = model.tab.example
        #expect(edited != original)
        #expect(manager.undoActionName == edit.rawValue)

        manager.undo()
        #expect(model.tab.example == original)
        #expect(!model.tab.isDirty)
        #expect(manager.levelsOfUndo == 0)

        manager.redo()
        #expect(model.tab.example == edited)
        #expect(model.tab.isDirty)
    }

    @Test func `an edit that changes nothing is no undo step`() {
        let model = model()
        let manager = manager()
        step(manager) {
            model.setExampleName("ok", undo: manager)
            model.setExampleStatus(200, undo: manager)
            // Out of range, and clamped back to what it was.
            model.setExampleStatus(200, undo: manager)
            model.setExampleDelay(10, undo: manager)
        }
        #expect(manager.levelsOfUndo == 0)
    }

    @Test func `an out-of-range status undoes to the value before it`() {
        let model = model()
        let manager = manager()
        step(manager) { model.setExampleStatus(700, undo: manager) }
        #expect(model.tab.example?.status == 599)
        manager.undo()
        #expect(model.tab.example?.status == 200)
    }

    @Test func `undo steps unwind in order`() {
        let model = model()
        let manager = manager()
        step(manager) { model.setExampleName("one", undo: manager) }
        step(manager) { model.setExampleName("two", undo: manager) }
        manager.undo()
        #expect(model.tab.example?.name == "one")
        manager.undo()
        #expect(model.tab.example?.name == "ok")
    }

    // MARK: Replace from File…

    @Test func `a UTF-8 file replaces the body as text`() throws {
        let model = model(files: ["/a.json": Data(#"{"a":1}"#.utf8)])
        try model.replaceExampleBody(fromFile: "/a.json")
        #expect(model.tab.example?.body == .text(#"{"a":1}"#))
    }

    @Test func `a binary file replaces the body as bytes`() throws {
        let png = Data([0x89, 0x50, 0x4E, 0x47, 0xFF])
        let model = model(files: ["/a.png": png])
        try model.replaceExampleBody(fromFile: "/a.png")
        #expect(model.tab.example?.body == .bytes(png))
    }

    @Test func `replacing the body is one undo step`() throws {
        let model = model(files: ["/a": Data([0xFF, 0xFE])])
        let manager = manager()
        manager.beginUndoGrouping()
        try model.replaceExampleBody(fromFile: "/a", undo: manager)
        manager.endUndoGrouping()
        #expect(manager.undoActionName == "Body")
        manager.undo()
        #expect(model.tab.example?.body == .text("{}"))
    }

    @Test func `a file that does not read changes nothing and says why`() {
        let model = model()
        let manager = manager()
        manager.beginUndoGrouping()
        #expect(throws: StoreError.unreadable(path: "/missing", reason: "No such file")) {
            try model.replaceExampleBody(fromFile: "/missing", undo: manager)
        }
        manager.endUndoGrouping()
        #expect(model.tab.example == original)
        #expect(manager.levelsOfUndo == 0)
    }

    // MARK: Save Body…

    @Test func `only a bytes body can be saved from an Example Tab`() {
        let model = model()
        #expect(!model.canSaveBody)
        #expect(model.bodyToSave == nil)
        model.setExampleBody(.bytes(Data([1, 2, 3])))
        #expect(model.canSaveBody)
        #expect(model.bodyToSave?.body == Data([1, 2, 3]))
        #expect(model.bodyToSave?.name == "response.json")
        model.setExampleBody(.bytes(Data()))
        #expect(!model.canSaveBody)
    }

    @Test func `the saved name takes its extension from the Content-Type`() {
        let model = model()
        model.setExampleHeaders([Row(name: "Content-Type", value: "application/pdf")])
        model.setExampleBody(.bytes(Data([1])))
        #expect(model.bodyToSave?.name == "response.pdf")
    }

    @Test func `the saved bytes are written as they are`() throws {
        let model = model()
        model.setExampleBody(.bytes(Data([0, 255, 128])))
        let writer = RecordingFileWriting()
        let target = URL(filePath: "/tmp/out.bin")
        try model.bodyToSave?.write(to: target, writer: writer)
        #expect(writer.writes.map(\.data) == [Data([0, 255, 128])])
    }
}

enum DraftOrRequest: Sendable { case draft, request }

enum Edit: String, CaseIterable, Sendable {
    case name = "Name", status = "Status", delay = "Delay", headers = "Headers", body = "Body"

    @MainActor func apply(_ model: TabModel, _ undo: UndoManager) {
        switch self {
        case .name: model.setExampleName("renamed", undo: undo)
        case .status: model.setExampleStatus(404, undo: undo)
        case .delay: model.setExampleDelay(900, undo: undo)
        case .headers: model.setExampleHeaders([], undo: undo)
        case .body: model.setExampleBody(.bytes(Data([9])), undo: undo)
        }
    }
}

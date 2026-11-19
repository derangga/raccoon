import AppKit
import Observation
@testable import Raccoon
import RaccoonData
import RaccoonDomain
import RaccoonTesting
import Testing

/// Request file writes that read first, so the definition and the Examples survive each other.
@MainActor
struct ExampleWriteTests {
    let base = SaveRequestTests()
    let id = OpenRequestTests.charge.id
    let path = "Payments API/Create charge.json"

    func example(_ n: Int, name: String = "ok") -> Example {
        Example(id: ExampleID(UUID(uuidString: "00000000-0000-4000-8000-00000000E\(String(format: "%03d", n))")!),
                name: name, status: 200, body: .text("{\"n\": \(n)}"))
    }

    func onDisk() throws -> Request {
        try RequestFile.decode(Data(contentsOf: base.file))
    }

    @Test func `Save on a Dirty Tab keeps three Examples written meanwhile`() throws {
        let (window, tab) = try base.openEdited()
        let three = [example(1), example(2), example(3)]
        for each in three { try window.addExample(each, to: id) }

        window.save(tab.tab.id)

        let file = try onDisk()
        #expect(file.examples == three)
        #expect(file.definition == tab.tab.definition)
        #expect(!tab.tab.isDirty)
    }

    @Test func `addExample leaves a Dirty Tab's definition and Dirty state alone`() throws {
        let (window, tab) = try base.openEdited()
        let definition = tab.tab.definition
        let baseline = tab.tab.baseline

        try window.addExample(example(1), to: id)

        #expect(tab.tab.definition == definition)
        #expect(tab.tab.baseline == baseline)
        #expect(tab.tab.isDirty)
        #expect(try onDisk().definition == OpenRequestTests.charge.definition)
        #expect(try onDisk().examples == [example(1)])
    }

    @Test func `a write of ours is recorded in the ledger`() throws {
        let (window, _) = try base.openEdited()

        try window.addExample(example(1), to: id)

        #expect(window.ledger.isOurs(path, try Data(contentsOf: base.file)))
    }

    @Test func `updateExample changes one Example and keeps the definition and the others`() throws {
        let (window, _) = try base.openEdited()
        for n in 1...3 { try window.addExample(example(n), to: id) }

        try window.updateExample(id, example(2).id) { $0.name = "renamed" }

        let file = try onDisk()
        #expect(file.examples.map(\.name) == ["ok", "renamed", "ok"])
        #expect(file.definition == OpenRequestTests.charge.definition)
    }

    @Test func `updateExample with a whole Example replaces it, and appends it again when gone`() throws {
        let (window, _) = try base.openEdited()
        try window.addExample(example(1), to: id)
        try window.addExample(example(2), to: id)

        try window.updateExample(id, example(1, name: "kept"))
        #expect(try onDisk().examples.map(\.name) == ["kept", "ok"])

        try window.removeExample(id, example(1).id)
        try window.updateExample(id, example(1, name: "back"))
        #expect(try onDisk().examples.map(\.name) == ["ok", "back"])
        #expect(try onDisk().examples.last?.id == example(1).id)
    }

    @Test func `removeExample removes one Example, and a missing id is no error`() throws {
        let (window, _) = try base.openEdited()
        try window.addExample(example(1), to: id)
        try window.addExample(example(2), to: id)

        try window.removeExample(id, example(1).id)
        try window.removeExample(id, example(1).id)

        #expect(try onDisk().examples == [example(2)])
        #expect(try onDisk().definition == OpenRequestTests.charge.definition)
    }

    @Test func `a Request that is not in the tree is requestGone`() throws {
        let (window, _) = try base.openEdited()

        #expect(throws: ExampleWriteError.requestGone) {
            try window.addExample(example(1), to: RequestID(UUID()))
        }
    }

    @Test func `an unreadable file is never written`() throws {
        let (window, tab) = try base.openEdited()
        let garbage = Data("not json".utf8)
        try garbage.write(to: base.file)

        #expect(throws: ExampleWriteError.self) { try window.addExample(example(1), to: id) }
        window.save(tab.tab.id)

        #expect(try Data(contentsOf: base.file) == garbage)
        guard case .notSaved = tab.notice else { Issue.record("no Not saved: \(String(describing: tab.notice))"); return }
        #expect(tab.tab.isDirty)
    }

    @Test func `a file that now carries another id is never written`() throws {
        let (window, _) = try base.openEdited()
        let other = RequestFile.encode(Request(id: RequestID(UUID()), name: "Create charge", definition: OpenRequestTests.charge.definition))
        try other.write(to: base.file)

        #expect(throws: ExampleWriteError.self) { try window.addExample(example(1), to: id) }

        #expect(try Data(contentsOf: base.file) == other)
    }

    @Test func `a failed Example write says why and leaves the file`() throws {
        let (window, _) = try base.openEdited()
        let folder = base.file.deletingLastPathComponent()
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: folder.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: folder.path) }
        let before = try Data(contentsOf: base.file)

        do {
            try window.addExample(example(1), to: id)
            Issue.record("did not throw")
        } catch {
            guard case .failed(let reason) = error else { Issue.record("wrong error \(error)"); return }
            #expect(!reason.isEmpty)
        }
        #expect(try Data(contentsOf: base.file) == before)
    }

    @Test func `an Examples-only change on disk does not touch a Request Tab`() async throws {
        let (window, tab) = try base.openEdited()
        let definition = tab.tab.definition
        let baseline = tab.tab.baseline
        let before = window.scanCount
        // What a pull would leave: the same definition, one more Example, written by someone else.
        var request = OpenRequestTests.charge
        request.examples = [example(1)]
        try RequestFile.encode(request).write(to: base.file)

        base.watch.emit([path])
        for _ in 0..<200 where window.scanCount == before { await Task.yield() }

        #expect(window.scanCount > before)
        #expect(tab.tab.definition == definition)
        #expect(tab.tab.baseline == baseline)
        #expect(tab.tab.isDirty)
        #expect(!tab.tab.isChangedOnDisk)
    }

    @Test func `the index lists the Examples at once after each write, with no scan`() throws {
        let (window, _) = try base.openEdited()
        func summaries() -> [ExampleSummary] {
            guard case .request(_, _, _, _, let examples)? = window.index.collections.first?.nodes.first else { return [] }
            return examples
        }

        try window.addExample(example(1), to: id)
        try window.addExample(example(2, name: "two"), to: id)
        #expect(summaries() == [ExampleSummary(example(1)), ExampleSummary(example(2, name: "two"))])

        try window.updateExample(id, example(1).id) { $0.status = 404 }
        #expect(summaries().first?.status == 404)

        try window.removeExample(id, example(1).id)
        #expect(summaries() == [ExampleSummary(example(2, name: "two"))])
        #expect(window.index.path(of: id) == path)
    }

    @Test func `a save of the definition alone does not rebuild the index`() throws {
        let (window, tab) = try base.openEdited()
        try window.addExample(example(1), to: id)
        let flag = Flag()
        withObservationTracking { _ = window.index } onChange: { flag.fired = true }

        window.save(tab.tab.id)

        #expect(!flag.fired)
    }
}

private final class Flag: @unchecked Sendable { var fired = false }

import Foundation
@testable import Raccoon
import RaccoonData
import RaccoonDomain
import RaccoonTesting
import Synchronization
import Testing

/// A DataFolderStore that records the Request reads made after `arm()`, and holds the first one
/// until `proceed` is signalled, so a test can cancel while the work is mid-read.
final class GatedStore: DataFolderStore, @unchecked Sendable {
    private let base: any DataFolderStore
    private let armed = Mutex(false)
    private let recorded = Mutex<[String]>([])
    let proceed = DispatchSemaphore(value: 0)

    init(base: any DataFolderStore) { self.base = base }

    func arm() { armed.withLock { $0 = true } }
    var reads: [String] { recorded.withLock { $0 } }

    func read(_ path: String) throws(StoreError) -> Data {
        if armed.withLock({ $0 }) {
            let first = recorded.withLock { reads in
                reads.append(path)
                return reads.count == 1
            }
            if first {
                proceed.wait()
            }
        }
        return try base.read(path)
    }

    func ensureExists() throws(StoreError) { try base.ensureExists() }
    func scan() throws(StoreError) -> DataFolderScan { try base.scan() }
    func write(_ data: Data, to path: String) throws(StoreError) { try base.write(data, to: path) }
    func move(_ path: String, to newPath: String) throws(StoreError) { try base.move(path, to: newPath) }
    func trash(_ path: String) throws(StoreError) { try base.trash(path) }
    func createDirectory(_ path: String) throws(StoreError) { try base.createDirectory(path) }
    func writeDirectory(_ contents: DataFolderScan, to path: String) throws(StoreError) { try base.writeDirectory(contents, to: path) }
}

/// prepareExport over a live store in a temp dir: the step stream, in order, and the plan.
@MainActor
struct PrepareExportTests {
    let temp = FileManager.default.temporaryDirectory.appending(path: "raccoon-\(UUID())")
    var root: URL { temp.appending(path: "Raccoon") }
    let exportID = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!

    func makeWindow(location: DataFolderLocation? = nil) -> WindowModel {
        let window = WindowModel(
            dataFolder: location ?? .test(root), folderWatch: ManualFolderWatch(),
            sessionStore: DiskSessionStore(directory: temp.appending(path: "Support"), root: root.path), secrets: InMemorySecretStore(),
            instants: FixedInstantSource(.now),
            makeTab: {
                TabModel(transport: ScriptedTransport(.failure(.timedOut(seconds: 60))), secrets: InMemorySecretStore(), files: DictionaryFileReading([:]),
                         instants: FixedInstantSource(.now), clipboard: RecordingClipboardWriter())
            }
        )
        window.loadDataFolder()
        return window
    }

    func request(_ name: String, headers: [Row] = []) -> Request {
        var definition = RequestDefinition.empty
        definition.url = "https://api.example/\(name)"
        definition.headers = headers
        return Request(id: RequestID(UUID()), name: name, definition: definition)
    }

    func put(_ request: Request, at path: String) throws {
        try put(RequestFile.encode(request), at: path)
    }

    func put(_ data: Data, at path: String) throws {
        let url = root.appending(path: path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url)
    }

    func steps(_ window: WindowModel, _ collection: String = "Payments") async throws -> [ExportStep] {
        var steps: [ExportStep] = []
        for await step in try #require(window.prepareExport(collection, id: exportID)) { steps.append(step) }
        return steps
    }

    func plan(_ steps: [ExportStep]) throws -> ExportPlan {
        guard case .scanned(let plan)? = steps.last else { throw Failed() }
        return plan
    }

    struct Failed: Error {}

    @Test func `the steps arrive in order, the last carrying the counts, the findings and the bytes`() async throws {
        try put(request("Create", headers: [Row(name: "Authorization", value: "Bearer abc")]), at: "Payments/Refunds/Create.json")
        try put(request("Capture"), at: "Payments/Capture.json")
        let window = makeWindow()

        let steps = try await steps(window)

        #expect(steps.count == 3)
        #expect(steps[0] == .read(count: 2))
        #expect(steps[1] == .formatted)
        let plan = try plan(steps)
        #expect(plan.requests == 2)
        #expect(plan.folders == 1)
        #expect(plan.findings == [CredentialFinding(request: "Create", place: .header("Authorization"))])
        #expect(plan.skipped == [])
        #expect(plan.dirtyRequests == [])
        // The bytes are the exporter's, for the Requests as sorted.
        #expect(plan.data == PostmanExporter.collection(plan.collection, id: exportID))
    }

    @Test func `the nodes are in the sidebar's order, Folders first then Requests by name`() async throws {
        try put(request("Request 10"), at: "Payments/Request 10.json")
        try put(request("Request 2"), at: "Payments/Request 2.json")
        try put(request("Zed"), at: "Payments/Zed Folder/Zed.json")
        try put(request("Alpha"), at: "Payments/Alpha Folder/Alpha.json")

        let plan = try plan(try await steps(makeWindow()))

        let names = plan.collection.nodes.map { node in
            switch node {
            case .folder(let name, _): name
            case .request(let request): request.name
            }
        }
        #expect(names == ["Alpha Folder", "Zed Folder", "Request 2", "Request 10"])
    }

    @Test func `an unreadable row is skipped with its reason, never read again, and a file that broke since the scan is skipped`() async throws {
        try put(request("Good"), at: "Payments/Good.json")
        try put(request("Gone"), at: "Payments/Gone.json")
        try put(request("Later"), at: "Payments/Later.json")
        try put(Data("{".utf8), at: "Payments/Broken.json")
        let window = makeWindow()
        try FileManager.default.removeItem(at: root.appending(path: "Payments/Gone.json"))
        try put(Data("[]".utf8), at: "Payments/Later.json")

        let steps = try await steps(window)
        let plan = try plan(steps)

        #expect(steps[0] == .read(count: 1))
        #expect(plan.requests == 1)
        #expect(plan.skipped.map(\.path) == ["Payments/Broken.json", "Payments/Gone.json", "Payments/Later.json"])
        #expect(plan.skipped[0].reason.hasPrefix("Not valid JSON at line"))
        #expect(!plan.skipped[1].reason.isEmpty)
        #expect(plan.skipped[2].reason.hasPrefix("Not a Raccoon Request"))
        #expect(plan.collection.requests.map(\.name) == ["Good"])
    }

    @Test func `a Request that is Dirty in a Tab is named from the index, matched by id, so a twin with the same name is not`() async throws {
        let edited = request("Same name")
        let twin = request("Same name")
        try put(edited, at: "Payments/A.json")
        try put(twin, at: "Payments/B.json")
        try put(request("Elsewhere"), at: "Other/Elsewhere.json")
        let window = makeWindow()
        window.openRequest(edited.id)
        window.selectedTab?.tab.definition.url = "https://changed.example"
        window.openRequest(twin.id)
        let other = try #require(window.index.collections.first { $0.name == "Other" }?.nodes.first)
        if case .request(let id, _, _, _) = other {
            window.openRequest(id)
            window.selectedTab?.tab.definition.url = "https://changed.example"
        }

        let plan = try plan(try await steps(window))

        #expect(plan.dirtyRequests == ["Same name"])
        // The file holds what is saved.
        #expect(plan.collection.requests.first { $0.id == edited.id }?.definition == edited.definition)
    }

    @Test func `a Collection no longer in the index opens nothing`() {
        #expect(makeWindow().prepareExport("Payments", id: exportID) == nil)
    }

    @Test func `stopping the consumer mid-read stops the reads: the rest of the files are never read`() async throws {
        for i in 1...20 { try put(request("Request \(i)"), at: "Payments/Request \(i).json") }
        let gated = GatedStore(base: DiskDataFolderStore(root: root))
        let window = makeWindow(location: DataFolderLocation(root: root.path, open: { _ in gated }, remember: { _ in }))
        gated.arm()
        let stream = try #require(window.prepareExport("Payments", id: exportID))
        let consumer = Task { for await _ in stream {} }

        while gated.reads.isEmpty { try await Task.sleep(for: .milliseconds(1)) }
        consumer.cancel()
        await consumer.value
        gated.proceed.signal()
        // Uncancelled, the other 19 reads take a few milliseconds.
        try await Task.sleep(for: .milliseconds(300))

        #expect(gated.reads.count == 1)
    }

    /// `example/` is untracked (it holds real tokens), so a clone without it skips this test.
    nonisolated static let sample = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appending(path: "example/Sociolla.postman_collection.json")

    @Test(.enabled(if: FileManager.default.fileExists(atPath: PrepareExportTests.sample.path)))
    func `the example Collection, imported, exports as 41 Requests, 11 Folders and 18 credentials`() async throws {
        let window = makeWindow()
        let imported = PostmanMapping.plan(
            [PostmanImporter.read(try Data(contentsOf: Self.sample))], dataFolder: window.index, globals: window.globals,
            environments: window.environments, newID: { RequestID(UUID()) }
        )
        _ = try window.importPostman(imported)

        let exported = try plan(try await steps(window, "Sociolla"))
        #expect(exported.requests == 41)
        #expect(exported.folders == 11)
        #expect(exported.findings.count == 18)
        #expect(exported.skipped == [])

        let model = CollectionExportModel(name: "Sociolla", folder: "~/Raccoon")
        #expect(model.counts(exported) == "41 Requests · 11 Folders")
        #expect(model.notices(exported).first?.headline == "18 credentials in plain text")
    }
}

import Foundation

/// The Session file's format. The bytes go through SessionStore; this is the only code that reads them.
public enum SessionFile {
    private struct Header: Decodable {
        var version: Int
    }

    private struct File: Codable {
        var version = 1
        var tabs: [TabJSON]?
        var selected: UUID?
        var activeEnvironment: String?
    }

    private struct TabJSON: Codable {
        var id: UUID
        /// Absent for a Draft.
        var requestID: UUID?
        /// With `requestID`, an Example Tab.
        var exampleID: UUID?
        /// A Draft's and a Request Tab's; absent for an Example Tab.
        var definition: DefinitionJSON?
        var baseline: DefinitionJSON?
        /// An Example Tab's, in the Request file's encoding; `exampleBaseline` absent is "not on disk".
        var example: ExampleJSON?
        var exampleBaseline: ExampleJSON?

        init(_ tab: TabSnapshot) {
            id = tab.id.rawValue
            requestID = tab.source.requestID?.rawValue
            if case .example(_, let example) = tab.source { exampleID = example.rawValue }
            switch (tab.content, tab.baseline) {
            case (.request(let definition), let baseline):
                self.definition = DefinitionJSON(definition)
                if case .request(let baseline)? = baseline { self.baseline = DefinitionJSON(baseline) }
            case (.example(let example), let baseline):
                self.example = ExampleJSON(example)
                if case .example(let baseline)? = baseline { exampleBaseline = ExampleJSON(baseline) }
            }
        }

        func snapshot() throws(Malformed) -> TabSnapshot {
            switch (requestID, exampleID) {
            case (nil, nil), (_?, nil):
                guard let definition else { throw Malformed(reason: "definition") }
                return TabSnapshot(
                    id: TabID(id), source: requestID.map { .request(RequestID($0)) } ?? .draft,
                    content: .request(try definition.definition()), baseline: try baseline.map { json throws(Malformed) in .request(try json.definition()) })
            case (let request?, let exampleID?):
                guard let example else { throw Malformed(reason: "example") }
                return TabSnapshot(
                    id: TabID(id), source: .example(RequestID(request), ExampleID(exampleID)),
                    content: .example(try example.example()), baseline: try exampleBaseline.map { json throws(Malformed) in .example(try json.example()) })
            case (nil, _?):
                throw Malformed(reason: "exampleID")
            }
        }
    }

    public static func encode(_ session: Session) -> Data {
        let file = File(
            tabs: session.tabs.map(TabJSON.init),
            selected: session.selected?.rawValue,
            activeEnvironment: session.activeEnvironment
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        // Only strings, numbers and bools: encoding cannot fail.
        return try! encoder.encode(file)
    }

    /// `version` is read first: an unknown one is undecodable, never guessed at.
    public static func decode(_ data: Data) throws(StoreError) -> Session {
        do {
            let version = try JSONDecoder().decode(Header.self, from: data).version
            guard version == 1 else { throw Malformed(reason: "unknown version \(version)") }
            let file = try JSONDecoder().decode(File.self, from: data)
            return Session(
                tabs: try (file.tabs ?? []).map { tab throws(Malformed) in try tab.snapshot() },
                selected: file.selected.map(TabID.init),
                activeEnvironment: file.activeEnvironment
            )
        } catch let error as Malformed {
            throw .undecodable(path: "session.json", reason: error.reason)
        } catch {
            throw .undecodable(path: "session.json", reason: String(describing: error))
        }
    }
}

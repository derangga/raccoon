import Foundation

/// session.json's format. The bytes go through SessionStore; this is the only code that reads them.
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
        var definition: DefinitionJSON
        var baseline: DefinitionJSON?
    }

    public static func encode(_ session: Session) -> Data {
        let file = File(
            tabs: session.tabs.map { tab in
                let requestID: UUID? = if case .request(let id) = tab.source { id.rawValue } else { nil }
                return TabJSON(id: tab.id.rawValue, requestID: requestID, definition: DefinitionJSON(tab.definition),
                               baseline: tab.baseline.map(DefinitionJSON.init))
            },
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
                tabs: try (file.tabs ?? []).map { tab in
                    TabSnapshot(id: TabID(tab.id), source: tab.requestID.map { .request(RequestID($0)) } ?? .draft,
                                definition: try tab.definition.definition(), baseline: try tab.baseline.map { json throws(Malformed) in try json.definition() })
                },
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

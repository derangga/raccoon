import Foundation

/// raccoon.json: `{ "version": 1, "id": "<UUID>", "mocks": { "<Collection name>": { "port": 8080,
/// "allowsCORS": true } } }`, committed with the Collections. `mocks` is written only when there
/// is something in it. The bytes go through DataFolderStore; this is the only code that reads them.
public enum WorkspaceFile {
    private struct Header: Decodable {
        var version: Int
    }

    /// One Collection's MockSettings. A value of the wrong type is absent, never a throw.
    private struct Entry: Codable {
        var port: UInt16?
        var allowsCORS: Bool

        init(_ settings: MockSettings) {
            port = settings.port
            allowsCORS = settings.allowsCORS
        }

        init(from decoder: any Decoder) {
            let container = try? decoder.container(keyedBy: CodingKeys.self)
            // UInt16 rejects a negative, fractional or over-65535 number, a string and null.
            port = try? container?.decodeIfPresent(UInt16.self, forKey: .port)
            allowsCORS = (try? container?.decodeIfPresent(Bool.self, forKey: .allowsCORS)) ?? true
        }
    }

    private struct File: Codable {
        var version = 1
        var id: UUID
        var mocks: [String: Entry]

        enum CodingKeys: CodingKey { case version, id, mocks }

        init(id: UUID, mocks: [String: Entry]) {
            self.id = id
            self.mocks = mocks
        }

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            id = try container.decode(UUID.self, forKey: .id)
            // A mocks that is not an object is no settings at all, not an undecodable file.
            mocks = (try? container.decodeIfPresent([String: Entry].self, forKey: .mocks)) ?? [:]
        }

        func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(version, forKey: .version)
            try container.encode(id, forKey: .id)
            if !mocks.isEmpty { try container.encode(mocks, forKey: .mocks) }
        }
    }

    /// The encoder RequestFile uses, so the file never changes in git once written.
    public static func encode(_ id: WorkspaceID, mocks: [String: MockSettings] = [:]) -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted, .withoutEscapingSlashes]
        let file = File(id: id.rawValue, mocks: mocks.mapValues(Entry.init))
        // A UUID, an Int, strings and numbers: encoding cannot fail.
        return try! encoder.encode(file) + Data("\n".utf8)
    }

    public static func decode(_ data: Data) throws(StoreError) -> WorkspaceID {
        try contents(data).id
    }

    /// `version` is read first: an unknown one is undecodable, never guessed at.
    public static func contents(_ data: Data) throws(StoreError) -> (id: WorkspaceID, mocks: [String: MockSettings]) {
        do {
            let version = try JSONDecoder().decode(Header.self, from: data).version
            guard version == 1 else { throw Malformed(reason: "unknown version \(version)") }
            let file = try JSONDecoder().decode(File.self, from: data)
            return (WorkspaceID(file.id), file.mocks.mapValues { MockSettings(port: $0.port, allowsCORS: $0.allowsCORS) })
        } catch let error as Malformed {
            throw .undecodable(path: "raccoon.json", reason: error.reason)
        } catch {
            throw .undecodable(path: "raccoon.json", reason: String(describing: error))
        }
    }

    /// A Collection with no entry has `.standard`.
    public static func settings(for collection: String, in mocks: [String: MockSettings]) -> MockSettings {
        mocks[collection] ?? .standard
    }

    /// The bytes with one Collection's settings replaced; the id and the other Collections stay.
    public static func replacing(_ settings: MockSettings, for collection: String, in data: Data) throws(StoreError) -> Data {
        var (id, mocks) = try contents(data)
        mocks[collection] = settings
        return encode(id, mocks: mocks)
    }
}

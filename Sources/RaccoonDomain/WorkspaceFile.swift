import Foundation

/// raccoon.json: `{ "version": 1, "id": "<UUID>" }`, committed with the Collections. The bytes go
/// through DataFolderStore; this is the only code that reads them.
public enum WorkspaceFile {
    private struct Header: Decodable {
        var version: Int
    }

    private struct File: Codable {
        var version = 1
        var id: UUID
    }

    /// The encoder RequestFile uses, so the file never changes in git once written.
    public static func encode(_ id: WorkspaceID) -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted, .withoutEscapingSlashes]
        // A UUID and an Int: encoding cannot fail.
        return try! encoder.encode(File(id: id.rawValue)) + Data("\n".utf8)
    }

    /// `version` is read first: an unknown one is undecodable, never guessed at.
    public static func decode(_ data: Data) throws(StoreError) -> WorkspaceID {
        do {
            let version = try JSONDecoder().decode(Header.self, from: data).version
            guard version == 1 else { throw Malformed(reason: "unknown version \(version)") }
            return WorkspaceID(try JSONDecoder().decode(File.self, from: data).id)
        } catch let error as Malformed {
            throw .undecodable(path: "raccoon.json", reason: error.reason)
        } catch {
            throw .undecodable(path: "raccoon.json", reason: String(describing: error))
        }
    }
}

import Foundation

/// A Request's file in the Data Folder: `version`, `id`, `name` and the definition's keys, flat.
/// The bytes go through DataFolderStore; this is the only code that reads them.
public enum RequestFile {
    private struct Header: Decodable {
        var version: Int
    }

    private struct Identity: Decodable {
        var id: UUID
        var name: String
    }

    /// The definition's keys and the identity's, in one object.
    private struct File: Encodable {
        var version = 1
        var id: UUID
        var name: String
        var definition: DefinitionJSON

        private enum Keys: String, CodingKey { case version, id, name }

        func encode(to encoder: any Encoder) throws {
            try definition.encode(to: encoder)
            var container = encoder.container(keyedBy: Keys.self)
            try container.encode(version, forKey: .version)
            try container.encode(id, forKey: .id)
            try container.encode(name, forKey: .name)
        }
    }

    /// Sorted keys and stable formatting: a save that changes nothing produces no git diff, and
    /// one changed header changes one line. Ends in a newline, as git expects of a text file.
    public static func encode(_ request: Request) -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted, .withoutEscapingSlashes]
        // Only strings, numbers and bools: encoding cannot fail.
        return try! encoder.encode(File(id: request.id.rawValue, name: request.name, definition: DefinitionJSON(request.definition)))
            + Data("\n".utf8)
    }

    /// `version` is read first: an unknown one is an error, never guessed at.
    public static func decode(_ data: Data) throws(RequestFileError) -> Request {
        do {
            let version = try JSONDecoder().decode(Header.self, from: data).version
            guard version == 1 else { throw RequestFileError.unknownVersion(version) }
            let identity = try JSONDecoder().decode(Identity.self, from: data)
            let definition = try JSONDecoder().decode(DefinitionJSON.self, from: data).definition()
            return Request(id: RequestID(identity.id), name: identity.name, definition: definition)
        } catch let error as RequestFileError {
            throw error
        } catch {
            throw .malformed(String(describing: error))
        }
    }
}

public enum RequestFileError: Error, Equatable, Sendable {
    case unknownVersion(Int)
    case malformed(String)
}

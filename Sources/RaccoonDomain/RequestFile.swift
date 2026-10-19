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
        let object: Any
        do {
            object = try JSONSerialization.jsonObject(with: data, options: .fragmentsAllowed)
        } catch {
            // Foundation gives the byte offset where parsing stopped; none means the end of the file.
            let offset = (error as NSError).userInfo["NSJSONSerializationErrorIndex"] as? Int ?? data.count
            throw .notJSON(line: 1 + data.prefix(offset).count { $0 == UInt8(ascii: "\n") })
        }
        guard object is [String: Any] else { throw .malformed("not a JSON object") }
        do {
            let version = try JSONDecoder().decode(Header.self, from: data).version
            guard version == 1 else { throw RequestFileError.unknownVersion(version) }
            let identity = try JSONDecoder().decode(Identity.self, from: data)
            let definition = try JSONDecoder().decode(DefinitionJSON.self, from: data).definition()
            return Request(id: RequestID(identity.id), name: identity.name, definition: definition)
        } catch let error as RequestFileError {
            throw error
        } catch let error as Malformed {
            throw .malformed(error.reason)
        } catch let error as DecodingError {
            throw .malformed(phrase(error))
        } catch {
            throw .malformed(String(describing: error))
        }
    }

    private static func phrase(_ error: DecodingError) -> String {
        let key = { (context: DecodingError.Context) in context.codingPath.map(\.stringValue).joined(separator: ".") }
        return switch error {
        case .keyNotFound(let missing, let context):
            "missing “\((context.codingPath + [missing]).map(\.stringValue).joined(separator: "."))”"
        case .typeMismatch(_, let context), .valueNotFound(_, let context): "“\(key(context))” has the wrong type"
        case .dataCorrupted(let context): "“\(key(context))” is not valid"
        @unknown default: String(describing: error)
        }
    }
}

public enum RequestFileError: Error, Equatable, Sendable {
    case notJSON(line: Int)
    case unknownVersion(Int)
    /// JSON, but not a Request: what is wrong with it, e.g. missing “name”.
    case malformed(String)

    /// The unreadable row's text (design-system §6 Sidebar rows).
    public var reason: String {
        switch self {
        case .notJSON(let line): "Not valid JSON at line \(line). Raccoon won't change this file."
        case .unknownVersion(let version): "Unknown file version \(version)."
        case .malformed(let what): "Not a Raccoon Request: \(what). Raccoon won't change this file."
        }
    }
}

/// A Request's file name is its name: `/` and `:` become `-`, and so does a leading `.`, which
/// would hide the file from the scan. A taken name gets " 2", " 3"…, compared without case
/// because APFS is case-insensitive by default.
public enum RequestFileName {
    /// A name as a file or folder name: `/`, `:` and a leading `.` become `-`.
    public static func sanitised(_ name: String) -> String {
        let base = name.replacing(/[\/:]/, with: "-")
        return base.hasPrefix(".") ? "-" + base.dropFirst() : base
    }

    public static func make(_ name: String, taken: Set<String>) -> String {
        precondition(!name.isEmpty, "the Save sheet requires a name")
        let base = sanitised(name)
        return unique(base, extension: ".json", taken: taken)
    }

    /// `base` + `ext`, or with " 2", " 3"… until no taken name matches, ignoring case.
    public static func unique(_ base: String, extension ext: String = "", taken: Set<String>) -> String {
        let taken = Set(taken.map { $0.lowercased() })
        var name = base + ext
        var n = 1
        while taken.contains(name.lowercased()) {
            n += 1
            name = "\(base) \(n)\(ext)"
        }
        return name
    }
}

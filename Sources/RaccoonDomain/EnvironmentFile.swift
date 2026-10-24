import Foundation

/// globals.json and environments/<name>.json: `{ "version": 1, "variables": [ … ] }`, each entry
/// a name, isEnabled, and either a value or `"secret": true` with none. The bytes go through
/// DataFolderStore; this is the only code that reads them.
public enum EnvironmentFile {
    public struct Decoded: Equatable, Sendable {
        public var entries: [VariableEntry]
        /// Secrets someone hand-edited a value into (boundary.md): the value is dropped.
        public var droppedSecretValues: [VariableName]
    }

    private struct Header: Decodable {
        var version: Int
    }

    private struct File: Codable {
        var version = 1
        var variables: [EntryJSON]?
    }

    private struct EntryJSON: Codable {
        var name: String
        var isEnabled: Bool?
        var value: String?
        var secret: Bool?
    }

    /// The encoder RequestFile uses, so a save that changes nothing produces no git diff.
    public static func encode(_ entries: [VariableEntry]) -> Data {
        let file = File(variables: entries.map { entry in
            switch entry.value {
            case .plain(let value): EntryJSON(name: entry.name.rawValue, isEnabled: entry.isEnabled, value: value)
            case .secret: EntryJSON(name: entry.name.rawValue, isEnabled: entry.isEnabled, secret: true)
            }
        })
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted, .withoutEscapingSlashes]
        // Only strings and bools: encoding cannot fail.
        return try! encoder.encode(file) + Data("\n".utf8)
    }

    /// `version` is read first: an unknown one is undecodable, never guessed at.
    public static func decode(_ data: Data, path: String) throws(StoreError) -> Decoded {
        do {
            do {
                _ = try JSONSerialization.jsonObject(with: data, options: .fragmentsAllowed)
            } catch {
                // Foundation gives the byte offset where parsing stopped; none means the end of the file.
                let offset = (error as NSError).userInfo["NSJSONSerializationErrorIndex"] as? Int ?? data.count
                throw Malformed(reason: "Not valid JSON at line \(1 + data.prefix(offset).count { $0 == UInt8(ascii: "\n") })")
            }
            let version = try JSONDecoder().decode(Header.self, from: data).version
            guard version == 1 else { throw Malformed(reason: "Unknown file version \(version)") }
            var decoded = Decoded(entries: [], droppedSecretValues: [])
            for json in try JSONDecoder().decode(File.self, from: data).variables ?? [] {
                guard let name = VariableName(json.name) else { throw Malformed(reason: "“\(json.name)” is not a Variable name") }
                let value: VariableEntry.Value
                switch (json.secret ?? false, json.value) {
                case (true, let dropped):
                    if dropped != nil { decoded.droppedSecretValues.append(name) }
                    value = .secret
                case (false, let plain?): value = .plain(plain)
                case (false, nil): throw Malformed(reason: "“\(json.name)” has neither a value nor \"secret\": true")
                }
                decoded.entries.append(VariableEntry(name: name, isEnabled: json.isEnabled ?? true, value: value))
            }
            return decoded
        } catch let error as Malformed {
            throw .undecodable(path: path, reason: error.reason)
        } catch let error as DecodingError {
            let phrase = RequestFile.phrase(error)
            throw .undecodable(path: path, reason: phrase.prefix(1).uppercased() + phrase.dropFirst())
        } catch {
            throw .undecodable(path: path, reason: String(describing: error))
        }
    }
}

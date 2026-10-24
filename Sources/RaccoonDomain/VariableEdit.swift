import Foundation

/// What the Environments sheet accepts as a Variable's name; nothing is written for a refusal.
public enum VariableEdit {
    public enum Refusal: Error, Equatable, Sendable {
        case invalidName
        case duplicate(VariableName)

        /// The line under the row. `set` is the Environment's name, nil for Globals.
        public func message(in set: String?) -> String {
            switch self {
            case .invalidName: "Names use letters, digits, _, - and . only."
            case .duplicate(let name): "\(name.rawValue) is already in \(set ?? "Globals")."
            }
        }
    }

    /// `text` as a name for the row at `replacing` (nil: a new row); no other row may carry it.
    public static func name(_ text: String, in entries: [VariableEntry], replacing index: Int?) throws(Refusal) -> VariableName {
        guard let name = VariableName(text.trimmingCharacters(in: .whitespaces)) else { throw .invalidName }
        guard !entries.enumerated().contains(where: { $0.offset != index && $0.element.name == name }) else { throw .duplicate(name) }
        return name
    }
}

public enum EnvironmentName {
    /// The existing Environment `proposed` would collide with, ignoring case because APFS does.
    /// `own` is the one being renamed, which may change only its case.
    public static func clash(_ proposed: String, among names: [String], except own: String?) -> String? {
        names.first { $0 != own && $0.lowercased() == proposed.lowercased() }
    }
}

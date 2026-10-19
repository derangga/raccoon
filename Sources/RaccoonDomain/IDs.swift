// Models, rules and port protocols. Foundation for value types only: no I/O (see LayeringTests).
import Foundation

/// Which Request a file is, written inside it. A path says where the Request is, not which one.
public struct RequestID: Hashable, Sendable {
    public let rawValue: UUID
    public init(_ rawValue: UUID) { self.rawValue = rawValue }
}

public struct TabID: Hashable, Sendable {
    public let rawValue: UUID
    public init(_ rawValue: UUID) { self.rawValue = rawValue }
}

/// Which Workspace a Data Folder is, written in its raccoon.json. Its Secret Variables follow it.
public struct WorkspaceID: Hashable, Sendable {
    public let rawValue: UUID
    public init(_ rawValue: UUID) { self.rawValue = rawValue }
}

/// The name inside `{{name}}`: ASCII letters and digits, `_`, `-` and `.`, never empty.
public struct VariableName: Hashable, Sendable {
    public let rawValue: String

    public init?(_ rawValue: String) {
        guard !rawValue.isEmpty, rawValue.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || "_-.".contains($0)) })
        else { return nil }
        self.rawValue = rawValue
    }
}

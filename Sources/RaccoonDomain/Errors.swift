import Foundation

public enum CurlImportError: Error, Equatable, Sendable {
    case unterminatedQuote(position: Int)
    case noURL
}

public enum ResolveError: Error, Equatable, Sendable {
    /// Every missing name, not the first.
    case undefined([VariableName])
    /// The URL text after substitution, because that is the one that failed.
    case invalidURL(String)
}

public enum SendError: Error, Equatable, Sendable {
    /// A multipart file part, read by the transport before any byte goes out.
    case fileMissing(path: String)
    case timedOut
    case untrustedCertificate(host: String)
    /// URLError's description, and host[:port] the send went to.
    case transport(URLError.Code, String, host: String)
}

public enum StoreError: Error, Equatable, Sendable {
    case unreadable(path: String, reason: String)
    case undecodable(path: String, reason: String)
    case unwritable(path: String, reason: String)
}

public enum SecretError: Error, Equatable, Sendable {
    case unavailable(OSStatus)
    /// The Workspace has no id, so there is no Keychain service to use: "raccoon.json can't be read".
    case raccoonJSONUnreadable
}

/// What Postman Import could not write, or wrote without a secret's value; the rest landed.
public enum ImportError: Error, Equatable, Sendable {
    /// Nothing of it remains. `name` is the folder name it was to have, as for an Environment.
    case collectionUnwritable(name: String, StoreError)
    /// The secrets stored for it were deleted again.
    case environmentUnwritable(name: String, StoreError)
    /// No Global was added.
    case globalsUnwritable(StoreError)
    /// Written as a secret with no value, undefined until set. `environment` nil is Globals.
    case secretNotStored(name: VariableName, environment: String?, SecretError)
}

/// Where a raw JSON or XML body stopped parsing; the text is left unchanged. 1-based.
public enum FormatError: Error, Equatable, Sendable {
    case notValid(line: Int, column: Int)
}

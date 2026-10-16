import Foundation

public enum CurlImportError: Error, Equatable, Sendable {
    case unterminatedQuote(position: Int)
    case noURL
}

public enum ResolveError: Error, Equatable, Sendable {
    /// Every missing name, not the first.
    case undefined([VariableName])
}

public enum SendError: Error, Equatable, Sendable {
    /// The URL after substitution, because that is the one that failed.
    case invalidURL(String)
    /// A multipart file part.
    case fileMissing(path: String)
    case timedOut
    case untrustedCertificate(host: String)
    case transport(URLError.Code, String)
}

public enum StoreError: Error, Equatable, Sendable {
    case unreadable(path: String, reason: String)
    case undecodable(path: String, reason: String)
    case unwritable(path: String, reason: String)
}

public enum SecretError: Error, Equatable, Sendable {
    case unavailable(OSStatus)
}

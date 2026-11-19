/// What raccoon.json remembers about one Collection's Mock Server. A Collection with no entry
/// has `.standard`: the system picks the port, browsers are allowed.
public struct MockSettings: Equatable, Sendable {
    public var port: UInt16?
    public var allowsCORS: Bool

    public init(port: UInt16?, allowsCORS: Bool) {
        self.port = port
        self.allowsCORS = allowsCORS
    }

    public static let standard = MockSettings(port: nil, allowsCORS: true)
}

import Foundation

/// One 3xx a send followed on its way to the Response. A redirect the send refused is not a
/// Redirect: it is the Response.
public struct Redirect: Equatable, Sendable {
    public var status: Int
    /// The method sent to `url`: what that request carried, after any rewrite on the way.
    public var method: String
    /// The URL that answered with this 3xx.
    public var url: URL
    /// Where URLSession offered to go next.
    public var location: URL
    /// Sorted by name, as the Response's are.
    public var headers: [Response.Header]

    public init(status: Int, method: String, url: URL, location: URL, headers: [Response.Header]) {
        self.status = status
        self.method = method
        self.url = url
        self.location = location
        self.headers = headers
    }
}

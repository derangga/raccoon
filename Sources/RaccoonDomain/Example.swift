import Foundation

/// A saved response of a Request, kept in the Request's file beside its definition (examples.md).
public struct Example: Equatable, Sendable {
    public let id: ExampleID
    public var name: String
    /// Assigning out of range clamps instead of failing, as RequestSettings' numbers do.
    public var status: Int {
        didSet { status = Self.statusRange.clamped(status) }
    }

    public var headers: [Row]
    public var body: ExampleBody
    public var delayMilliseconds: Int {
        didSet { delayMilliseconds = Self.delayRange.clamped(delayMilliseconds) }
    }

    public static let statusRange = 100...599
    public static let delayRange = 0...60000

    public init(
        id: ExampleID, name: String, status: Int, headers: [Row] = [],
        body: ExampleBody, delayMilliseconds: Int = 0
    ) {
        self.id = id
        self.name = name
        // Clamped here as well as in didSet: a didSet does not run on an init's own assignment.
        self.status = Self.statusRange.clamped(status)
        self.headers = headers
        self.body = body
        self.delayMilliseconds = Self.delayRange.clamped(delayMilliseconds)
    }
}

extension Example {
    /// Save as Example (examples.md): "200 OK", the status, the headers and the body as the Response
    /// holds them. URLSession decoded the body and the Mock Server frames its own reply, so the four
    /// framing headers would lie. The Response's redirects are not kept: only the final one is saved.
    public static func from(_ response: Response, id: ExampleID) -> Example {
        let reason = StatusLine(status: response.status, elapsed: .zero, byteCount: 0).reason
        let framing: Set<String> = ["content-encoding", "content-length", "transfer-encoding", "connection"]
        return Example(
            id: id, name: reason.isEmpty ? "\(response.status)" : "\(response.status) \(reason)", status: response.status,
            headers: response.headers.filter { !framing.contains($0.name.lowercased()) }.map { Row(name: $0.name, value: $0.value) },
            body: ExampleBody(bytes: response.body))
    }

    /// What the Response viewer draws to show this Example (examples.md §Show an Example): the status,
    /// the enabled headers and the body's bytes. Nothing was measured, so the elapsed time is zero.
    public var asResponse: Response {
        let bytes: Data = switch body {
        case .text(let text): Data(text.utf8)
        case .bytes(let data): data
        }
        return Response(
            status: status, headers: headers.filter(\.isEnabled).map { Response.Header(name: $0.name, value: $0.value) },
            body: bytes, elapsed: .zero, byteCount: bytes.count)
    }

    /// Duplicate (examples.md): the same Example under a new id, " 2" appended to the name as it stands.
    public func duplicate(id: ExampleID) -> Example {
        Example(id: id, name: name + " 2", status: status, headers: headers, body: body, delayMilliseconds: delayMilliseconds)
    }

    /// The `Content-Type` header's value: the first enabled row of that name, in any case.
    public var contentType: String? {
        headers.first { $0.isEnabled && $0.name.caseInsensitiveCompare("Content-Type") == .orderedSame }?.value
    }

    /// What colours a text body: JSON for `json` and `+json` subtypes, XML for `xml` and `+xml`, else plain.
    public var bodySyntax: RawKind {
        guard let media = contentType?.split(separator: ";").first else { return .text }
        let subtype = media.lowercased().split(separator: "/").last.map(String.init) ?? ""
        if subtype == "json" || subtype.hasSuffix("+json") { return .json }
        if subtype == "xml" || subtype.hasSuffix("+xml") { return .xml }
        return .text
    }
}

/// `.text` when the bytes are UTF-8, `.bytes` otherwise.
public enum ExampleBody: Equatable, Sendable {
    case text(String)
    case bytes(Data)

    /// Total: the UTF-8 rule for a Response, and for a file read to replace a body.
    public init(bytes data: Data) {
        self = String(data: data, encoding: .utf8).map(Self.text) ?? .bytes(data)
    }
}

/// An Example as JSON: in a Request file's `examples`, and later in the Session. Every wrong
/// shape is `Malformed("examples")` and a repeated id is `Malformed("duplicate Example id")`, so
/// the file is unreadable as a whole, never half-read.
struct ExampleJSON: Codable {
    var id: UUID
    var name: String
    var status: Int
    var headers: [DefinitionJSON.RowJSON]
    var body: BodyJSON
    /// Left out when 0.
    var delayMilliseconds: Int?

    /// Exactly one of `text` and `base64`.
    struct BodyJSON: Codable {
        var text: String?
        var base64: String?
    }

    init(_ example: Example) {
        id = example.id.rawValue
        name = example.name
        status = example.status
        headers = example.headers.map(DefinitionJSON.RowJSON.init)
        body = switch example.body {
        case .text(let text): BodyJSON(text: text)
        case .bytes(let data): BodyJSON(base64: data.base64EncodedString())
        }
        delayMilliseconds = example.delayMilliseconds == 0 ? nil : example.delayMilliseconds
    }

    func example() throws(Malformed) -> Example {
        let body: ExampleBody
        switch (self.body.text, self.body.base64) {
        case (let text?, nil): body = .text(text)
        case (nil, let encoded?):
            guard let data = Data(base64Encoded: encoded) else { throw Malformed(reason: "examples") }
            body = .bytes(data)
        default: throw Malformed(reason: "examples")
        }
        return Example(
            id: ExampleID(id), name: name, status: status, headers: headers.map(\.row),
            body: body, delayMilliseconds: delayMilliseconds ?? 0)
    }

    /// `examples` of a Request file's object; absent is none. Any entry that does not decode, and
    /// a repeated id, throw.
    static func examples(in data: Data) throws(Malformed) -> [Example] {
        struct Keys: Decodable { var examples: [ExampleJSON]? }
        let json: [ExampleJSON]
        do { json = try JSONDecoder().decode(Keys.self, from: data).examples ?? [] } catch { throw Malformed(reason: "examples") }
        let examples = try json.map { entry throws(Malformed) in try entry.example() }
        guard Set(examples.map(\.id)).count == examples.count else { throw Malformed(reason: "duplicate Example id") }
        return examples
    }
}

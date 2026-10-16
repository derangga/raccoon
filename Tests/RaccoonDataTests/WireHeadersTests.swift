import Foundation
@testable import RaccoonData
import RaccoonDomain
import RaccoonTesting
import Testing

/// What goes on the wire is the Headers table's enabled rows plus AutomaticHeaders, nothing else.
struct WireHeadersTests {
    static let cases: [(String, String, [Row], Body)] = [
        ("GET, no rows", "GET", [], .none),
        ("raw JSON with its Content-Type row", "POST", [Row(name: "Content-Type", value: "application/json"), Row(name: "X-A", value: "1")], .raw(.json, "{}")),
        ("raw text, no Content-Type row", "POST", [], .raw(.text, "hi")),
        ("empty raw body", "POST", [Row(name: "Content-Type", value: "text/plain")], .raw(.text, "")),
        ("form, no Content-Type row", "POST", [], .formURLEncoded([Row(name: "a", value: "1")])),
        ("multipart, no Content-Type row", "POST", [], .multipart([Part(name: "a", content: .text("1"))])),
        ("rows replace and a Disabled Row does not", "GET",
         [Row(name: "User-Agent", value: "curl/8"), Row(name: "Accept", value: "x", isEnabled: false), Row(name: "Accept-Language", value: "id")], .none),
    ]

    @Test(arguments: [false, true], cases.map(\.0))
    func `the wire is the enabled rows plus the automatic rows`(tls: Bool, name: String) async throws {
        let (_, method, headers, body) = try #require(Self.cases.first { $0.0 == name })
        try await withEchoServer(tls: tls) { server in
            var definition = RequestDefinition.empty
            definition.method = method
            definition.url = server.url("/echo").absoluteString
            definition.headers = headers
            definition.body = body
            definition.settings.allowsInsecureTLS = true
            let resolved = try VariableResolver.resolve(definition)

            _ = try await URLSessionTransport(files: DictionaryFileReading([:])).send(resolved)

            let wire = try Self.headers(#require(server.requests.last))
            let shown = resolved.definition.headers.map { ($0.name, Optional($0.value)) }
                + AutomaticHeaders.rows(for: resolved).map { ($0.name, $0.value) }
            #expect(wire.keys.sorted() == shown.map { $0.0.lowercased() }.sorted())
            for (name, value) in shown {
                guard let value else { continue }  // computed at send: present is enough
                #expect(wire[name.lowercased()] == value, "\(name)")
            }
        }
    }

    /// Lowercased name → value, multipart's boundary cut off as editing.md allows.
    static func headers(_ request: Data) -> [String: String] {
        let head = String(decoding: request, as: UTF8.self).components(separatedBy: "\r\n\r\n")[0]
        var headers: [String: String] = [:]
        for line in head.components(separatedBy: "\r\n").dropFirst() {
            let colon = line.firstIndex(of: ":")!
            let value = line[colon...].dropFirst().trimmingCharacters(in: .whitespaces)
            headers[line[..<colon].lowercased()] = value.hasPrefix("multipart/form-data; boundary=") ? "multipart/form-data" : value
        }
        return headers
    }
}

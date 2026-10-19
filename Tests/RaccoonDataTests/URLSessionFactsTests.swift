import Foundation
@testable import RaccoonData
@testable import RaccoonDomain
import RaccoonTesting
import Testing

/// What URLSession does on its own, measured against the echo server. Each test is a row in
/// design/environment-facts.md; one failing means a new OS changed the fact and the design that
/// leans on it has to be read again.
struct URLSessionFactsTests {
    func send(_ server: EchoServer, _ definition: RequestDefinition = .empty) async throws -> Data {
        var definition = definition
        definition.settings.allowsInsecureTLS = true
        let transport = URLSessionTransport(files: DictionaryFileReading([:]))
        _ = try await transport.send(ResolvedRequest(definition: definition, url: server.url("/echo")))
        return try #require(server.requests.last)
    }

    /// The request's header lines as sent, in wire order.
    func headers(_ request: Data) -> [(name: String, value: String)] {
        let head = String(decoding: request, as: UTF8.self).components(separatedBy: "\r\n\r\n")[0]
        return head.components(separatedBy: "\r\n").dropFirst().map {
            let colon = $0.firstIndex(of: ":")!
            return (String($0[..<colon]), $0[colon...].dropFirst().trimmingCharacters(in: .whitespaces))
        }
    }

    func value(_ name: String, in request: Data) -> String? {
        headers(request).first { $0.name == name }?.value
    }

    @Test func `a GET with no headers set goes out with six headers URLSession added`() async throws {
        try await withEchoServer { server in
            // The bare session: the transport replaces User-Agent and Accept-Language.
            let transport = URLSessionTransport(files: DictionaryFileReading([:]))
            defer { withExtendedLifetime(transport) {} }  // its deinit invalidates the session
            _ = try await transport.session.data(from: server.url("/echo"))
            let request = try #require(server.requests.last)

            #expect(Set(headers(request).map(\.name)) == ["Host", "Accept", "Accept-Language", "Connection", "Accept-Encoding", "User-Agent"])
            #expect(value("Accept", in: request) == "*/*")
            #expect(value("Connection", in: request) == "keep-alive")
            #expect(value("Accept-Encoding", in: request) == "gzip, deflate")
            #expect(value("User-Agent", in: request)?.contains("CFNetwork/") == true)
            #expect(value("Accept-Language", in: request)?.isEmpty == false)
        }
    }

    @Test func `over TLS Accept-Encoding also offers br`() async throws {
        try await withEchoServer(tls: true) { server in
            let request = try await send(server)
            #expect(value("Accept-Encoding", in: request) == "gzip, deflate, br")
        }
    }

    @Test func `a body with no Content-Type row goes out as application x-www-form-urlencoded`() async throws {
        try await withEchoServer { server in
            var post = RequestDefinition.empty
            post.method = "POST"
            post.body = .raw(.text, "hi")

            let request = try await send(server, post)

            #expect(value("Content-Type", in: request) == "application/x-www-form-urlencoded")
            #expect(value("Content-Length", in: request) == "2")
        }
    }

    @Test func `a GET with a body is refused before any byte goes out`() async throws {
        try await withEchoServer { server in
            var get = RequestDefinition.empty
            get.body = .raw(.text, "a=1")
            await #expect {
                try await send(server, get)
            } throws: { error in
                guard case SendError.transport(.dataLengthExceedsMaximum, _, _) = error else { return false }
                return true
            }
            #expect(server.requests.isEmpty)
        }
    }

    @Test func `a GET with an empty body goes out with no body`() async throws {
        try await withEchoServer { server in
            var get = RequestDefinition.empty
            get.body = .raw(.text, "")
            let request = try await send(server, get)
            #expect(String(decoding: request, as: UTF8.self).hasSuffix("\r\n\r\n"))
            #expect(value("Content-Length", in: request) == nil)
        }
    }

    @Test func `a DELETE with a body is sent, with no Content-Type added`() async throws {
        try await withEchoServer { server in
            var delete = RequestDefinition.empty
            delete.method = "DELETE"
            delete.body = .raw(.text, "a=1")
            let request = try await send(server, delete)
            #expect(String(decoding: request, as: UTF8.self).hasSuffix("\r\n\r\na=1"))
            #expect(value("Content-Length", in: request) == "3")
            #expect(value("Content-Type", in: request) == nil)
        }
    }

    @Test(arguments: ["PUT", "PATCH"])
    func `a PUT or PATCH with a body is sent, with no Content-Type added`(method: String) async throws {
        try await withEchoServer { server in
            var definition = RequestDefinition.empty
            definition.method = method
            definition.body = .raw(.text, "a=1")
            let request = try await send(server, definition)
            #expect(String(decoding: request, as: UTF8.self).hasSuffix("\r\n\r\na=1"))
            #expect(value("Content-Length", in: request) == "3")
            #expect(value("Content-Type", in: request) == nil)
        }
    }

    @Test func `a Cookie header set by hand is sent with no cookie storage`() async throws {
        try await withEchoServer { server in
            var definition = RequestDefinition.empty
            definition.headers = [Row(name: "Cookie", value: "manual=1")]

            let request = try await send(server, definition)
            #expect(value("Cookie", in: request) == "manual=1")
        }
    }

    @Test func `a Set-Cookie reply adds no cookie to the next request`() async throws {
        try await withEchoServer { server in
            let transport = URLSessionTransport(files: DictionaryFileReading([:]))
            _ = try await transport.send(ResolvedRequest(definition: .empty, url: server.url("/headers")))

            let request = try await send(server)
            #expect(value("Cookie", in: request) == nil)
        }
    }

    @Test func `HTTPURLResponse merges duplicate headers and keeps no wire order`() async throws {
        try await withEchoServer { server in
            let transport = URLSessionTransport(files: DictionaryFileReading([:]))
            defer { withExtendedLifetime(transport) {} }  // its deinit invalidates the session
            let (_, response) = try await transport.session.data(from: server.url("/headers"))
            let http = try #require(response as? HTTPURLResponse)

            // Sent: Z-Last, Set-Cookie a, A-First, Set-Cookie b (EchoServer.replyHeaders).
            #expect(http.value(forHTTPHeaderField: "Set-Cookie") == "a=1; Path=/, b=2; Path=/")
            #expect(http.allHeaderFields["Set-Cookie"] as? String == "a=1; Path=/, b=2; Path=/")
            #expect(http.allHeaderFields.count == 6)  // a dictionary: one Set-Cookie key, no order
        }
    }

    @Test(arguments: [nil, "identity", "gzip"])
    func `a gzip reply arrives decoded whatever Accept-Encoding asked for`(acceptEncoding: String?) async throws {
        try await withEchoServer { server in
            var definition = RequestDefinition.empty
            definition.headers = acceptEncoding.map { [Row(name: "Accept-Encoding", value: $0)] } ?? []
            let transport = URLSessionTransport(files: DictionaryFileReading([:]))

            let response = try await transport.send(ResolvedRequest(definition: definition, url: server.url("/gzip")))

            let request = try #require(server.requests.last)
            #expect(value("Accept-Encoding", in: request) == acceptEncoding ?? "gzip, deflate")
            #expect(String(decoding: response.body, as: UTF8.self) == "compressed hello")
            // byteCount is the decoded size; the wire carried 36 bytes.
            #expect(response.byteCount == 16)
            #expect(response.headers.contains(.init(name: "Content-Length", value: "36")))
            #expect(response.headers.contains(.init(name: "Content-Encoding", value: "gzip")))
        }
    }

    @Test func `cancelling the Task closes the connection at once and throws cancelled`() async throws {
        try await withEchoServer { server in
            let transport = URLSessionTransport(files: DictionaryFileReading([:]))
            let request = ResolvedRequest(definition: .empty, url: server.url("/delay/10000"))
            let send = Task<SendError?, Never> {
                do throws(SendError) { _ = try await transport.send(request); return nil } catch { return error }
            }
            try await Task.sleep(for: .seconds(1))
            let cancelledAt = ContinuousClock.now
            send.cancel()

            let error = await send.value
            let returnedAt = ContinuousClock.now
            try await Task.sleep(for: .milliseconds(200))

            guard case .transport(.cancelled, _, _) = error else { Issue.record("\(String(describing: error))"); return }
            #expect(returnedAt - cancelledAt < .milliseconds(200))
            let closedAt = try #require(server.closes.first)
            #expect(closedAt - cancelledAt < .milliseconds(200))
            #expect(server.requests.count == 1)
        }
    }
}

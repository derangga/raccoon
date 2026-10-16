import Foundation
@testable import RaccoonData
@testable import RaccoonDomain
import RaccoonTesting
import Testing

/// The live transport against the echo server: what URLSession actually puts on the wire.
struct URLSessionTransportTests {
    func resolved(
        _ server: EchoServer, _ path: String, method: String = "GET", headers: [Row] = [], cookies: [Row] = [],
        body: Body = .none, settings: RequestSettings = RequestDefinition.empty.settings
    ) -> ResolvedRequest {
        var definition = RequestDefinition.empty
        definition.method = method
        definition.headers = headers
        definition.cookies = cookies
        definition.body = body
        definition.settings = settings
        return ResolvedRequest(definition: definition, url: server.url(path))
    }

    func transport(files: [String: Data] = [:], timeout: Duration = .seconds(60)) -> URLSessionTransport {
        URLSessionTransport(files: DictionaryFileReading(files), timeout: timeout)
    }

    @Test func `a GET returns status, headers and body bytes unchanged`() async throws {
        try await withEchoServer { server in
            let response = try await transport().send(resolved(server, "/echo"))

            #expect(response.status == 200)
            #expect(response.headers.contains(.init(name: "Content-Type", value: "application/octet-stream")))
            #expect(server.requests == [response.body])
            #expect(response.byteCount == response.body.count)
        }
    }

    @Test func `headers keep their order, cookies go out as one Cookie header`() async throws {
        try await withEchoServer { server in
            let request = resolved(server, "/echo",
                headers: [Row(name: "X-B", value: "2"), Row(name: "X-A", value: "1")],
                cookies: [Row(name: "a", value: "1"), Row(name: "b", value: "2")])

            let text = String(decoding: try await transport().send(request).body, as: UTF8.self)

            #expect(text.contains("\r\nCookie: a=1; b=2\r\n"))
            let b = try #require(text.range(of: "\r\nX-B: 2\r\n"))
            let a = try #require(text.range(of: "\r\nX-A: 1\r\n"))
            #expect(b.lowerBound < a.lowerBound)
        }
    }

    @Test func `a form body is percent-encoded`() async throws {
        try await withEchoServer { server in
            let request = resolved(server, "/echo", method: "POST",
                body: .formURLEncoded([Row(name: "q", value: "a&b c"), Row(name: "n", value: "1")]))

            let text = String(decoding: try await transport().send(request).body, as: UTF8.self)

            #expect(text.hasSuffix("\r\n\r\nq=a%26b%20c&n=1"))
        }
    }

    @Test func `multipart reads file parts and appends the boundary to Content-Type`() async throws {
        try await withEchoServer { server in
            let request = resolved(server, "/echo", method: "POST",
                headers: [Row(name: "Content-Type", value: "multipart/form-data")],
                body: .multipart([Part(name: "note", content: .text("hi")), Part(name: "doc", content: .file(path: "/tmp/r.pdf"))]))

            let text = String(decoding: try await transport(files: ["/tmp/r.pdf": Data("PDF".utf8)]).send(request).body, as: UTF8.self)

            let boundary = try #require(text.firstMatch(of: /Content-Type: multipart\/form-data; boundary=(\S+)\r\n/)?.1)
            #expect(text.contains("--\(boundary)\r\nContent-Disposition: form-data; name=\"note\"\r\n\r\nhi\r\n"))
            #expect(text.contains("Content-Disposition: form-data; name=\"doc\"; filename=\"r.pdf\"\r\nContent-Type: application/octet-stream\r\n\r\nPDF\r\n"))
            #expect(text.hasSuffix("--\(boundary)--\r\n"))
        }
    }

    @Test func `a missing file part fails before any byte goes out`() async throws {
        try await withEchoServer { server in
            let request = resolved(server, "/echo", method: "POST", body: .multipart([Part(name: "doc", content: .file(path: "/gone.pdf"))]))

            await #expect(throws: SendError.fileMissing(path: "/gone.pdf")) { try await transport().send(request) }
            #expect(server.requests.isEmpty)
        }
    }

    @Test func `redirects are followed only when the Request Setting says so`() async throws {
        try await withEchoServer { server in
            var settings = RequestDefinition.empty.settings
            let refused = try await transport().send(resolved(server, "/redirect", settings: settings))
            #expect(refused.status == 302)

            settings.followsRedirects = true
            let followed = try await transport().send(resolved(server, "/redirect", settings: settings))
            #expect(followed.status == 200)
        }
    }

    @Test func `a self-signed host fails unless insecure TLS is allowed`() async throws {
        try await withEchoServer(tls: true) { server in
            var settings = RequestDefinition.empty.settings
            await #expect(throws: SendError.untrustedCertificate(host: "127.0.0.1")) {
                try await transport().send(resolved(server, "/echo", settings: settings))
            }

            settings.allowsInsecureTLS = true
            let response = try await transport().send(resolved(server, "/echo", settings: settings))
            #expect(response.status == 200)
        }
    }

    @Test func `a reply past the timeout fails with timedOut and is never retried`() async throws {
        try await withEchoServer { server in
            await #expect(throws: SendError.timedOut) {
                try await transport(timeout: .milliseconds(200)).send(resolved(server, "/delay/1000"))
            }
            #expect(server.requests.count == 1)
        }
    }

    @Test func `the session keeps no cookies, cache or credentials`() {
        let configuration = transport().session.configuration
        #expect(configuration.httpCookieStorage == nil)
        #expect(configuration.urlCache == nil)
        #expect(configuration.urlCredentialStorage == nil)
        #expect(configuration.timeoutIntervalForRequest == 60)
    }
}

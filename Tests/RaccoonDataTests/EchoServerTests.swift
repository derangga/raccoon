import Foundation
import Testing

/// The echo server itself, measured with a bare URLSession so the transport is not involved.
struct EchoServerTests {
    let session = URLSession(configuration: .ephemeral)

    @Test func `the server stops when its scope ends`() async throws {
        let url = try await withEchoServer { server in
            let (_, response) = try await session.data(from: server.url("/echo"))
            #expect((response as? HTTPURLResponse)?.statusCode == 200)
            return server.url("/echo")
        }
        await #expect {
            _ = try await session.data(from: url)
        } throws: { error in
            (error as? URLError)?.code == .cannotConnectToHost
        }
    }

    @Test func `echo returns the exact bytes the server received`() async throws {
        try await withEchoServer { server in
            var request = URLRequest(url: server.url("/echo"))
            request.httpMethod = "POST"
            request.setValue("1", forHTTPHeaderField: "X-Raccoon")
            request.httpBody = Data("hello".utf8)

            let (body, _) = try await session.data(for: request)

            #expect(server.requests == [body])
            let text = String(decoding: body, as: UTF8.self)
            #expect(text.hasPrefix("POST /echo HTTP/1.1\r\n"))
            #expect(text.contains("\r\nX-Raccoon: 1\r\n"))
            #expect(text.hasSuffix("\r\n\r\nhello"))
        }
    }

    @Test func `a delayed reply outlasts a short timeout`() async throws {
        try await withEchoServer { server in
            var request = URLRequest(url: server.url("/delay/1000"))
            request.timeoutInterval = 0.2
            await #expect {
                _ = try await session.data(for: request)
            } throws: { error in
                (error as? URLError)?.code == .timedOut
            }
        }
    }

    @Test func `TLS uses a self-signed certificate`() async throws {
        try await withEchoServer(tls: true) { server in
            await #expect {
                _ = try await session.data(from: server.url("/echo"))
            } throws: { error in
                (error as? URLError)?.code == .serverCertificateUntrusted
            }

            let (_, response) = try await session.data(from: server.url("/echo"), delegate: TestTaskDelegate(trustsAnyServer: true))
            #expect((response as? HTTPURLResponse)?.statusCode == 200)
        }
    }

    @Test func `redirect answers 302 to echo`() async throws {
        try await withEchoServer { server in
            let (_, refused) = try await session.data(from: server.url("/redirect"), delegate: TestTaskDelegate(followsRedirects: false))
            #expect((refused as? HTTPURLResponse)?.statusCode == 302)
            #expect((refused as? HTTPURLResponse)?.value(forHTTPHeaderField: "Location") == "/echo")

            let (_, followed) = try await session.data(from: server.url("/redirect"))
            #expect(followed.url?.path == "/echo")
            let requestLines = server.requests.map { String(decoding: $0.prefix { $0 != UInt8(ascii: "\r") }, as: UTF8.self) }
            #expect(requestLines == ["GET /redirect HTTP/1.1", "GET /redirect HTTP/1.1", "GET /echo HTTP/1.1"])
        }
    }

    @Test func `bytes returns a body of the chosen size`() async throws {
        try await withEchoServer { server in
            let (body, _) = try await session.data(from: server.url("/bytes/300000"))
            #expect(body.count == 300_000)
        }
    }
}

/// Answers the two questions a test needs answered differently from URLSession's defaults.
final class TestTaskDelegate: NSObject, URLSessionTaskDelegate {
    let trustsAnyServer: Bool
    let followsRedirects: Bool

    init(trustsAnyServer: Bool = false, followsRedirects: Bool = true) {
        self.trustsAnyServer = trustsAnyServer
        self.followsRedirects = followsRedirects
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didReceive challenge: URLAuthenticationChallenge) async
        -> (URLSession.AuthChallengeDisposition, URLCredential?) {
        guard trustsAnyServer, let trust = challenge.protectionSpace.serverTrust else { return (.performDefaultHandling, nil) }
        return (.useCredential, URLCredential(trust: trust))
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest) async -> URLRequest? {
        followsRedirects ? request : nil
    }
}

import Foundation
import Synchronization
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

    // MARK: Redirects

    /// Records every redirect URLSession offers, and follows up to `limit` of them.
    final class RedirectWatcher: NSObject, URLSessionTaskDelegate {
        let offered = Mutex<[URLRequest]>([])
        let limit: Int

        init(limit: Int = 50) {
            self.limit = limit
        }

        func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                        newRequest request: URLRequest) async -> URLRequest? {
            let count = offered.withLock { $0.append(request); return $0.count }
            return count <= limit ? request : nil
        }
    }

    /// A POST whose Authorization and body are on the wire, sent to a redirect of the given status.
    func redirected(_ server: EchoServer, status: Int, watcher: RedirectWatcher) async throws -> URLRequest {
        var request = URLRequest(url: server.url("/redirect/\(status)"))
        request.httpMethod = "POST"
        request.httpBody = Data("a=1".utf8)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer secret", forHTTPHeaderField: "Authorization")
        request.setValue("keep", forHTTPHeaderField: "X-Custom")
        let session = URLSession(configuration: .ephemeral)
        defer { session.finishTasksAndInvalidate() }
        _ = try await session.data(for: request, delegate: watcher)
        return try #require(watcher.offered.withLock { $0.first })
    }

    @Test(arguments: [301, 302, 303])
    func `a 301 302 or 303 is offered as a GET with no body`(status: Int) async throws {
        try await withEchoServer { server in
            let watcher = RedirectWatcher()
            let offered = try await redirected(server, status: status, watcher: watcher)

            #expect(offered.httpMethod == "GET")
            #expect(offered.httpBody == nil)
            #expect(offered.value(forHTTPHeaderField: "Content-Type") == nil)
            #expect(offered.value(forHTTPHeaderField: "X-Custom") == "keep")
            #expect(value("Authorization", in: try #require(server.requests.last)) == nil)
        }
    }

    @Test(arguments: [307, 308])
    func `a 307 or 308 keeps the method and sends the body again, though the delegate sees no body`(status: Int) async throws {
        try await withEchoServer { server in
            let watcher = RedirectWatcher()
            let offered = try await redirected(server, status: status, watcher: watcher)

            #expect(offered.httpMethod == "POST")
            #expect(offered.value(forHTTPHeaderField: "Content-Type") == "application/json")
            // URLSession carries the body itself: it is on the wire but not on the offered request.
            #expect(offered.httpBody == nil)
            let sent = try #require(server.requests.last)
            #expect(String(decoding: sent, as: UTF8.self).hasSuffix("a=1"))
            #expect(value("Content-Length", in: sent) == "3")
        }
    }

    /// The reason Request Settings cannot offer a redirect limit above 20.
    @Test func `URLSession stops after 20 redirects of its own accord`() async throws {
        try await withEchoServer { server in
            let watcher = RedirectWatcher()
            let session = URLSession(configuration: .ephemeral)
            defer { session.finishTasksAndInvalidate() }

            await #expect {
                _ = try await session.data(from: server.url("/loop"), delegate: watcher)
            } throws: { ($0 as? URLError)?.code == .httpTooManyRedirects }
            #expect(watcher.offered.withLock { $0.count } == 20)
        }
    }

    /// The reason the cap cannot throw from inside the delegate: refusing one succeeds.
    @Test func `returning nil from the delegate answers with the 3xx, not an error`() async throws {
        try await withEchoServer { server in
            let watcher = RedirectWatcher(limit: 3)
            let session = URLSession(configuration: .ephemeral)
            defer { session.finishTasksAndInvalidate() }

            let (_, response) = try await session.data(from: server.url("/loop"), delegate: watcher)
            #expect((response as? HTTPURLResponse)?.statusCode == 302)
            #expect(watcher.offered.withLock { $0.count } == 4)
        }
    }

    @Test func `a request's own timeout overrides the session configuration`() async throws {
        try await withEchoServer { server in
            let configuration = URLSessionConfiguration.ephemeral
            configuration.timeoutIntervalForRequest = 60
            let session = URLSession(configuration: configuration)
            defer { session.finishTasksAndInvalidate() }
            var request = URLRequest(url: server.url("/delay/3000"))
            request.timeoutInterval = 1

            let start = ContinuousClock.now
            await #expect { _ = try await session.data(for: request) } throws: { ($0 as? URLError)?.code == .timedOut }
            #expect(ContinuousClock.now - start < .seconds(2))
        }
    }

    // MARK: Metrics

    /// Keeps the metrics of the task it was passed to. Trusts the echo server's self-signed certificate.
    final class MetricsWatcher: NSObject, URLSessionTaskDelegate {
        let collected = Mutex<URLSessionTaskMetrics?>(nil)

        func urlSession(_ session: URLSession, task: URLSessionTask, didFinishCollecting metrics: URLSessionTaskMetrics) {
            collected.withLock { $0 = metrics }
        }

        func urlSession(_ session: URLSession, task: URLSessionTask, didReceive challenge: URLAuthenticationChallenge) async
            -> (URLSession.AuthChallengeDisposition, URLCredential?) {
            guard let trust = challenge.protectionSpace.serverTrust else { return (.performDefaultHandling, nil) }
            return (.useCredential, URLCredential(trust: trust))
        }
    }

    /// The transport's session: ephemeral, with no cache and no cookies.
    func transportSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.urlCache = nil
        return URLSession(configuration: configuration)
    }

    /// One send with its own watcher, as the transport does. `metrics` is read the instant `data(for:delegate:)` returns, with no wait.
    func measured(_ session: URLSession, _ url: URL) async throws -> (body: Data, metrics: URLSessionTaskMetrics?) {
        let watcher = MetricsWatcher()
        let (body, _) = try await session.data(for: URLRequest(url: url), delegate: watcher)
        return (body, watcher.collected.withLock { $0 })
    }

    @Test func `the delegate has the metrics by the time data(for:delegate:) returns`() async throws {
        try await withEchoServer { server in
            let session = transportSession()
            defer { session.finishTasksAndInvalidate() }
            // 60 sends, three kinds, none ever late: the callback runs before the async call resumes.
            for path in ["/echo", "/chain/3", "/gzip"] {
                for _ in 0..<20 {
                    let (_, metrics) = try await measured(session, server.url(path))
                    #expect(metrics != nil)
                }
            }
        }
    }

    @Test(arguments: [0, 1, 3, 19])
    func `after N followed redirects there are N + 1 transactions, in send order, each with its response`(redirects: Int) async throws {
        try await withEchoServer { server in
            let session = transportSession()
            defer { session.finishTasksAndInvalidate() }

            let metrics = try #require(try await measured(session, server.url("/chain/\(redirects)")).metrics)
            let transactions = metrics.transactionMetrics

            #expect(transactions.count == redirects + 1)
            #expect(transactions.map { $0.request.url?.path } == (0...redirects).reversed().map { "/chain/\($0)" })
            #expect(transactions.map { ($0.response as? HTTPURLResponse)?.statusCode } == Array(repeating: 302, count: redirects) + [200])
            #expect(transactions.map { $0.response?.url?.path } == (0...redirects).reversed().map { "/chain/\($0)" })
            let starts = transactions.compactMap(\.fetchStartDate)
            #expect(starts == starts.sorted())
            #expect(metrics.redirectCount == redirects)
        }
    }

    /// The most URLSession follows is 20 (the redirect cap), and the metrics keep only the last 20 transactions.
    @Test func `after 20 followed redirects the metrics hold 20 transactions and have dropped the first request`() async throws {
        try await withEchoServer { server in
            let session = transportSession()
            defer { session.finishTasksAndInvalidate() }

            let metrics = try #require(try await measured(session, server.url("/chain/20")).metrics)
            let transactions = metrics.transactionMetrics

            #expect(server.requests.count == 21)
            #expect(transactions.count == 20)
            #expect(transactions.first?.request.url?.path == "/chain/19")
            #expect(transactions.last?.response?.url?.path == "/chain/0")
            #expect(metrics.redirectCount == 19)
        }
    }

    /// With a cache a repeated send adds a transaction served from it, so the Timeline must come from a session with no cache.
    @Test func `with the default ephemeral cache a repeated redirect chain gains a local cache transaction`() async throws {
        try await withEchoServer { server in
            let session = URLSession(configuration: .ephemeral)
            defer { session.finishTasksAndInvalidate() }

            let first = try #require(try await measured(session, server.url("/chain/3")).metrics)
            let second = try #require(try await measured(session, server.url("/chain/3")).metrics)

            #expect(first.transactionMetrics.count == 4)
            #expect(second.transactionMetrics.count == 5)
            #expect(second.transactionMetrics.filter { $0.resourceFetchType == .localCache }.count == 1)
        }
    }

    @Test func `countOfResponseBodyBytesReceived is the gzip size on the wire, smaller than the body data(for:) returns`() async throws {
        try await withEchoServer { server in
            let session = transportSession()
            defer { session.finishTasksAndInvalidate() }

            let (body, metrics) = try await measured(session, server.url("/gzip"))
            let transaction = try #require(metrics?.transactionMetrics.last)

            #expect(EchoServer.gzipBody.count == 36)
            #expect(body.count == 16)
            #expect(transaction.countOfResponseBodyBytesReceived == 36)
            #expect(transaction.countOfResponseBodyBytesAfterDecoding == 16)
        }
    }

    /// A second send on the same session reuses the connection, so there is no DNS, connect or TLS phase to draw.
    @Test(arguments: [false, true])
    func `a second send over a kept-alive connection has no lookup, connect or TLS dates`(tls: Bool) async throws {
        try await withEchoServer(tls: tls) { server in
            let session = transportSession()
            defer { session.finishTasksAndInvalidate() }

            let first = try #require(try await measured(session, server.url("/keepalive")).metrics?.transactionMetrics.last)
            let second = try #require(try await measured(session, server.url("/keepalive")).metrics?.transactionMetrics.last)

            #expect(first.isReusedConnection == false)
            #expect(first.domainLookupStartDate != nil && first.domainLookupEndDate != nil)
            #expect(first.connectStartDate != nil && first.connectEndDate != nil)
            #expect((first.secureConnectionStartDate != nil && first.secureConnectionEndDate != nil) == tls)

            #expect(second.isReusedConnection)
            #expect(second.domainLookupStartDate == nil && second.domainLookupEndDate == nil)
            #expect(second.connectStartDate == nil && second.connectEndDate == nil)
            #expect(second.secureConnectionStartDate == nil && second.secureConnectionEndDate == nil)
            #expect(second.fetchStartDate != nil && second.requestStartDate != nil && second.responseEndDate != nil)
            #expect(server.requests.count == 2)
        }
    }

    @Test(arguments: [false, true])
    func `the protocol is http 1.1, TLS 1.3 only over TLS, and the fetch, request and response dates are always set`(tls: Bool) async throws {
        try await withEchoServer(tls: tls) { server in
            let session = transportSession()
            defer { session.finishTasksAndInvalidate() }

            let metrics = try #require(try await measured(session, server.url("/chain/3")).metrics)

            for transaction in metrics.transactionMetrics {
                #expect(transaction.resourceFetchType == .networkLoad)
                #expect(transaction.networkProtocolName == "http/1.1")
                #expect(transaction.negotiatedTLSProtocolVersion == (tls ? .TLSv13 : nil))
                #expect(transaction.fetchStartDate != nil)
                #expect(transaction.requestStartDate != nil)
                #expect(transaction.requestEndDate != nil)
                #expect(transaction.responseStartDate != nil)
                #expect(transaction.responseEndDate != nil)
            }
        }
    }
}

import Foundation
import RaccoonDomain

/// The live HTTPTransport: one URLSession for the app, and a delegate per send that answers
/// redirects and server trust from that request's Request Settings. It sends exactly once and
/// decodes nothing: the Response is the status, the headers and the body bytes.
///
/// Auth is not read here: the resolver has already turned it into a header.
public final class URLSessionTransport: HTTPTransport {
    let session: URLSession
    private let files: any FileReading

    /// No cookie storage, URL cache or credential storage: each is state the user cannot see.
    public init(files: any FileReading, timeout: Duration = .seconds(60)) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCache = nil
        configuration.urlCredentialStorage = nil
        configuration.timeoutIntervalForRequest = Double(timeout.components.seconds) + Double(timeout.components.attoseconds) / 1e18
        session = URLSession(configuration: configuration)
        self.files = files
    }

    deinit {
        session.finishTasksAndInvalidate()
    }

    public func send(_ request: ResolvedRequest) async throws(SendError) -> Response {
        let urlRequest = try urlRequest(for: request)
        let delegate = SendDelegate(settings: request.definition.settings)
        let start = ContinuousClock.now
        let (body, response) = try await lifting(host: request.url.host() ?? "") {
            try await session.data(for: urlRequest, delegate: delegate)
        }
        guard let http = response as? HTTPURLResponse else {
            throw .transport(.badServerResponse, "The server's reply was not HTTP.")
        }
        // allHeaderFields is a dictionary that joins duplicates with ", ", and no API keeps wire
        // order (environment-facts.md), so the headers are sorted by name.
        let headers = (http.allHeaderFields as? [String: String] ?? [:])
            .map { Response.Header(name: $0.key, value: $0.value) }
            .sorted { $0.name < $1.name }
        return Response(status: http.statusCode, headers: headers, body: body, elapsed: .now - start, byteCount: body.count)
    }

    private func urlRequest(for request: ResolvedRequest) throws(SendError) -> URLRequest {
        let definition = request.definition
        var urlRequest = URLRequest(url: request.url)
        urlRequest.httpMethod = definition.method
        var headers = definition.headers

        switch definition.body {
        case .none:
            break
        case .raw(_, let text):
            urlRequest.httpBody = Data(text.utf8)
        case .formURLEncoded(let rows):
            urlRequest.httpBody = Data(rows.map { "\(Self.formEncoded($0.name))=\(Self.formEncoded($0.value))" }.joined(separator: "&").utf8)
        case .multipart(let parts):
            let boundary = "raccoon-\(UUID().uuidString)"
            urlRequest.httpBody = try multipartBody(parts, boundary: boundary)
            let index = headers.firstIndex { $0.name.caseInsensitiveCompare("Content-Type") == .orderedSame }
            let mediaType = index.map { headers[$0].value.split(separator: ";").first.map(String.init) ?? "" } ?? "multipart/form-data"
            let contentType = Row(name: "Content-Type", value: "\(mediaType); boundary=\(boundary)")
            if let index { headers[index] = contentType } else { headers.append(contentType) }
        }

        for header in headers {
            urlRequest.addValue(header.value, forHTTPHeaderField: header.name)
        }
        // URLSession's own values carry build numbers and a system list nobody can show ahead, so
        // these two are set to what the Headers table's automatic rows say (AutomaticHeaders).
        for (name, value) in [("User-Agent", AutomaticHeaders.userAgent), ("Accept-Language", AutomaticHeaders.acceptLanguage)]
        where urlRequest.value(forHTTPHeaderField: name) == nil {
            urlRequest.setValue(value, forHTTPHeaderField: name)
        }
        // Request Cookies and any Cookie row are one header: addValue would join them with ", ".
        if !definition.cookies.isEmpty {
            let cookies = [urlRequest.value(forHTTPHeaderField: "Cookie")].compactMap { $0 } + definition.cookies.map { "\($0.name)=\($0.value)" }
            urlRequest.setValue(cookies.joined(separator: "; "), forHTTPHeaderField: "Cookie")
        }
        return urlRequest
    }

    /// Every file part is read before the request exists, so a missing file sends nothing.
    private func multipartBody(_ parts: [Part], boundary: String) throws(SendError) -> Data {
        var body = Data()
        for part in parts {
            body.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(Self.quoted(part.name))\"".utf8))
            switch part.content {
            case .text(let text):
                body.append(Data("\r\n\r\n\(text)\r\n".utf8))
            case .file(let path):
                let data: Data
                do throws(StoreError) { data = try files.read(path) } catch { throw .fileMissing(path: path) }
                let filename = Self.quoted(URL(filePath: path).lastPathComponent)
                body.append(Data("; filename=\"\(filename)\"\r\nContent-Type: application/octet-stream\r\n\r\n".utf8))
                body.append(data)
                body.append(Data("\r\n".utf8))
            }
        }
        body.append(Data("--\(boundary)--\r\n".utf8))
        return body
    }

    private static let formAllowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")

    private static func formEncoded(_ text: String) -> String {
        text.addingPercentEncoding(withAllowedCharacters: formAllowed) ?? text
    }

    /// A quote or line break would end the header; they are percent-encoded as browsers do.
    private static func quoted(_ text: String) -> String {
        text.replacing("\"", with: "%22").replacing("\r", with: "%0D").replacing("\n", with: "%0A")
    }

    /// URLSession's errors, lifted into SendError. Cancellation stays `.transport(.cancelled)`;
    /// the Tab treats it as `.idle`, not as a failure.
    private func lifting<A>(host: String, _ body: () async throws -> A) async throws(SendError) -> A {
        do {
            return try await body()
        } catch let error as URLError {
            switch error.code {
            case .timedOut:
                throw .timedOut
            case .serverCertificateUntrusted, .serverCertificateHasUnknownRoot, .serverCertificateHasBadDate,
                 .serverCertificateNotYetValid:
                throw .untrustedCertificate(host: host)
            default:
                throw .transport(error.code, error.localizedDescription)
            }
        } catch {
            throw .transport(.unknown, error.localizedDescription)
        }
    }
}

/// Answers one send's redirect and server-trust questions from its Request Settings.
private final class SendDelegate: NSObject, URLSessionTaskDelegate, Sendable {
    let settings: RequestSettings

    init(settings: RequestSettings) {
        self.settings = settings
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest) async -> URLRequest? {
        settings.followsRedirects ? request : nil
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didReceive challenge: URLAuthenticationChallenge) async
        -> (URLSession.AuthChallengeDisposition, URLCredential?) {
        guard settings.allowsInsecureTLS, let trust = challenge.protectionSpace.serverTrust else { return (.performDefaultHandling, nil) }
        return (.useCredential, URLCredential(trust: trust))
    }
}

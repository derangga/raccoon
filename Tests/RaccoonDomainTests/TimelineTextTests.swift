import Foundation
import Testing

@testable import RaccoonDomain

struct TimelineTextTests {
    func response(
        status: Int = 200, url: String? = "https://a.example/home", method: String? = "GET",
        headers: [Response.Header] = [.init(name: "Content-Type", value: "text/html")], redirects: [Redirect] = [],
        timing: Timing? = nil, byteCount: Int = 0
    ) -> Response {
        Response(status: status, headers: headers, body: Data(), elapsed: .milliseconds(5), byteCount: byteCount,
                 url: url.flatMap(URL.init(string:)), method: method, redirects: redirects, timing: timing)
    }

    let login = Redirect(
        status: 302, method: "GET", url: URL(string: "https://a.example/login")!, location: URL(string: "https://a.example/home")!,
        headers: [.init(name: "Location", value: "/home"), .init(name: "Set-Cookie", value: "sid=1; Path=/")])

    @Test func `a send with no redirect has one block, the Response, without its headers`() {
        let blocks = TimelineText.blocks(response())

        #expect(blocks == [
            .init(code: "200", reason: "OK", token: .status2xx, fields: ["GET", "https://a.example/home"], rows: [],
                  phases: TimelineText.notReported),
        ])
        #expect(blocks[0].statusText == "200 OK")
        #expect(blocks[0].line == "200 OK · GET · https://a.example/home")
    }

    @Test func `each Redirect is a block before the Response, with its Location and then its headers`() {
        let blocks = TimelineText.blocks(response(redirects: [login]))

        #expect(blocks.map(\.line) == [
            "302 Found · GET · https://a.example/login",
            "200 OK · GET · https://a.example/home",
        ])
        #expect(blocks[0].token == .status3xx)
        #expect(blocks[0].rows == [
            .init(name: "Location", value: "https://a.example/home"),
            .init(name: "Location", value: "/home"),
            .init(name: "Set-Cookie", value: "sid=1; Path=/"),
        ])
        #expect(blocks[1].rows.isEmpty)
    }

    @Test func `the method and the URL the Response does not know are left out, not guessed`() {
        #expect(TimelineText.blocks(response(url: nil, method: nil))[0].line == "200 OK")
        #expect(TimelineText.blocks(response(method: nil))[0].line == "200 OK · https://a.example/home")
        #expect(TimelineText.blocks(response(url: nil))[0].line == "200 OK · GET")
    }

    @Test func `a code with no registered reason shows the code alone`() {
        #expect(TimelineText.blocks(response(status: 299))[0].line == "299 · GET · https://a.example/home")
    }

    @Test func `a failing Response keeps its status color`() {
        #expect(TimelineText.blocks(response(status: 404))[0].token == .status4xx)
    }

    @Test func `two redirects come in the order they were followed`() {
        let second = Redirect(status: 301, method: "POST", url: URL(string: "https://a.example/home")!,
                              location: URL(string: "https://a.example/app")!, headers: [])
        let blocks = TimelineText.blocks(response(url: "https://a.example/app", redirects: [login, second]))

        #expect(blocks.map(\.line) == [
            "302 Found · GET · https://a.example/login",
            "301 Moved Permanently · POST · https://a.example/home",
            "200 OK · GET · https://a.example/app",
        ])
        #expect(blocks[1].rows == [.init(name: "Location", value: "https://a.example/app")])
    }

    @Test func `the merged-headers note shows once, only when a Redirect has headers`() {
        let bare = Redirect(status: 301, method: "GET", url: login.url, location: login.location, headers: [])

        #expect(TimelineText.showsHeadersNote(response(redirects: [login])))
        #expect(TimelineText.showsHeadersNote(response(redirects: [bare, login])))
        #expect(!TimelineText.showsHeadersNote(response(redirects: [bare])))
        #expect(!TimelineText.showsHeadersNote(response()))
        #expect(TimelineText.headersNote == "macOS merges repeated headers and doesn't keep their order.")
    }

    // MARK: Timing and Wire Size

    static let reported = Timing(
        dns: .milliseconds(4), connect: .milliseconds(12), tls: .milliseconds(18), send: .zero, waiting: .milliseconds(10),
        download: .milliseconds(1), total: .milliseconds(48), protocolName: "h2", remoteAddress: "93.184.216.34:443",
        tlsVersion: "TLS 1.3", bodyBytesOnWire: 420)

    var timedLogin: Redirect {
        var redirect = login
        redirect.timing = Self.reported
        return redirect
    }

    @Test func `a Timing adds the request's total to line 1 and gives the phases and the connection`() {
        let block = TimelineText.blocks(response(redirects: [timedLogin], timing: Self.reported))[0]

        #expect(block.line == "302 Found · GET · https://a.example/login · 48 ms")
        #expect(block.phases == "DNS 4 ms · Connect 12 ms · TLS 18 ms · Send 0 ms · Waiting 10 ms · Download 1 ms")
        #expect(block.connection == "h2 · 93.184.216.34:443 · TLS 1.3")
        #expect(block.size == nil)
    }

    @Test func `a reused connection says so in place of DNS, Connect and TLS`() {
        var timing = Self.reported
        (timing.dns, timing.connect, timing.tls, timing.reusedConnection) = (nil, nil, nil, true)

        #expect(TimelineText.blocks(response(timing: timing))[0].phases == "Reused connection · Send 0 ms · Waiting 10 ms · Download 1 ms")
    }

    @Test func `a phase that did not happen is left out, plain HTTP has no TLS`() {
        var timing = Self.reported
        (timing.tls, timing.tlsVersion, timing.waiting, timing.protocolName) = (nil, nil, nil, "http/1.1")
        let block = TimelineText.blocks(response(timing: timing))[0]

        #expect(block.phases == "DNS 4 ms · Connect 12 ms · Send 0 ms · Download 1 ms")
        #expect(block.connection == "http/1.1 · 93.184.216.34:443")
    }

    @Test func `a Timing with nothing known has neither a total, phases nor a connection`() {
        let block = TimelineText.blocks(response(timing: Timing()))[0]

        #expect(block.line == "200 OK · GET · https://a.example/home")
        #expect(block.phases == nil)
        #expect(block.connection == nil)
    }

    @Test func `the size line is the Response's alone, and only when the Wire Size differs`() {
        let blocks = TimelineText.blocks(response(redirects: [timedLogin], timing: Self.reported, byteCount: 1_200))

        #expect(blocks[0].size == nil)
        #expect(blocks[1].size == "1.2 KB · 420 B on the wire")
        #expect(TimelineText.blocks(response(timing: Self.reported, byteCount: 420))[0].size == nil)
        var unknown = Self.reported
        unknown.bodyBytesOnWire = nil
        #expect(TimelineText.blocks(response(timing: unknown, byteCount: 1_200))[0].size == nil)
    }

    @Test func `with no Timing for the send, every block says so`() {
        let blocks = TimelineText.blocks(response(redirects: [login]))

        #expect(blocks.map(\.phases) == ["Timing was not reported for this send.", "Timing was not reported for this send."])
        #expect(blocks.map(\.connection) == [nil, nil])
        #expect(blocks[0].line == "302 Found · GET · https://a.example/login")
    }

    @Test func `when only some requests have a Timing, the others have no phases line`() {
        let blocks = TimelineText.blocks(response(redirects: [login], timing: Self.reported))

        #expect(blocks[0].phases == nil)
        #expect(blocks[1].phases == "DNS 4 ms · Connect 12 ms · TLS 18 ms · Send 0 ms · Waiting 10 ms · Download 1 ms")
    }
}

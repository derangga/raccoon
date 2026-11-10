import Foundation
import Testing

@testable import RaccoonDomain

struct TimelineTextTests {
    func response(
        status: Int = 200, url: String? = "https://a.example/home", method: String? = "GET",
        headers: [Response.Header] = [.init(name: "Content-Type", value: "text/html")], redirects: [Redirect] = []
    ) -> Response {
        Response(status: status, headers: headers, body: Data(), elapsed: .milliseconds(5), byteCount: 0,
                 url: url.flatMap(URL.init(string:)), method: method, redirects: redirects)
    }

    let login = Redirect(
        status: 302, method: "GET", url: URL(string: "https://a.example/login")!, location: URL(string: "https://a.example/home")!,
        headers: [.init(name: "Location", value: "/home"), .init(name: "Set-Cookie", value: "sid=1; Path=/")])

    @Test func `a send with no redirect has one block, the Response, without its headers`() {
        let blocks = TimelineText.blocks(response())

        #expect(blocks == [
            .init(code: "200", reason: "OK", token: .status2xx, fields: ["GET", "https://a.example/home"], rows: []),
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
}

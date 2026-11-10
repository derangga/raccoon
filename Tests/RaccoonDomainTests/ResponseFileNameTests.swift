import Foundation
import RaccoonDomain
import Testing

struct ResponseFileNameTests {
    func suggest(disposition: String? = nil, contentType: String? = nil, url: String? = nil) -> String {
        var headers: [Response.Header] = []
        if let disposition { headers.append(.init(name: "Content-Disposition", value: disposition)) }
        if let contentType { headers.append(.init(name: "content-type", value: contentType)) }
        return ResponseFileName.suggest(headers: headers, url: url.flatMap { URL(string: $0) })
    }

    @Test(arguments: [
        (#"attachment; filename="report.pdf""#, "report.pdf"),
        ("attachment; filename=report.pdf", "report.pdf"),
        (#"attachment; filename="my report.pdf""#, "my report.pdf"),
        (#"attachment; filename="semi;colon.txt""#, "semi;colon.txt"),
        (#"attachment; filename="say \"hi\".txt""#, #"say "hi".txt"#),
        (#"ATTACHMENT; FileName="Report.PDF"; size=3"#, "Report.PDF"),
        ("attachment; filename*=UTF-8''r%C3%A9.pdf", "ré.pdf"),
        ("attachment; filename*=utf-8'en'caf%C3%A9.txt", "café.txt"),
    ])
    func `the Content-Disposition name is read, quoted, bare or RFC 8187`(disposition: String, expected: String) {
        #expect(suggest(disposition: disposition, url: "https://a.example/other.bin") == expected)
    }

    @Test func `filename* beats filename whatever order they come in`() {
        #expect(suggest(disposition: #"attachment; filename="plain.pdf"; filename*=UTF-8''r%C3%A9.pdf"#) == "ré.pdf")
        #expect(suggest(disposition: #"attachment; filename*=UTF-8''r%C3%A9.pdf; filename="plain.pdf""#) == "ré.pdf")
    }

    @Test func `an unusable filename* falls back to filename`() {
        #expect(suggest(disposition: #"attachment; filename*=UTF-8''..%2Fx; filename="ok.txt""#) == "ok.txt")
        #expect(suggest(disposition: #"attachment; filename*=KOI8-R''x; filename="ok.txt""#) == "ok.txt")
    }

    @Test func `without a Content-Disposition name the URL's last path component is used, decoded`() {
        #expect(suggest(url: "https://a.example/files/r%C3%A9sum%C3%A9.pdf?v=2#top") == "résumé.pdf")
        #expect(suggest(disposition: "inline", url: "https://a.example/files/data.csv") == "data.csv")
        #expect(suggest(url: "https://a.example/files/") == "files")
    }

    @Test(arguments: [
        #"attachment; filename="../x""#, #"attachment; filename="a/b.txt""#, #"attachment; filename="c:evil.txt""#,
        #"attachment; filename="""#, #"attachment; filename=".""#, #"attachment; filename="..""#,
        "attachment; filename=\"tab\there.txt\"", "attachment; filename*=UTF-8''a%0Ab.txt",
    ])
    func `an unsafe name is rejected and the next source is tried`(disposition: String) {
        #expect(suggest(disposition: disposition, url: "https://a.example/safe.txt") == "safe.txt")
        #expect(suggest(disposition: disposition) == "response")
    }

    @Test(arguments: ["https://a.example/", "https://a.example", "https://a.example/a/..", "https://a.example/%2E%2E", "https://a.example/a%2Fb"])
    func `an unusable URL path falls through to response`(url: String) {
        #expect(suggest(url: url) == "response")
    }

    @Test func `nothing at all is response`() {
        #expect(suggest() == "response")
        #expect(ResponseFileName.suggest(headers: [], url: nil) == "response")
    }

    @Test(arguments: [
        ("application/pdf", "response.pdf"),
        ("Application/PDF; charset=binary", "response.pdf"),
        ("image/png", "response.png"),
        ("application/octet-stream", "response"),
        ("x-unknown/thing", "response"),
    ])
    func `a name with no extension gets one from the Content-Type when there is one`(contentType: String, expected: String) {
        #expect(suggest(contentType: contentType) == expected)
    }

    @Test func `a name that already has an extension keeps it`() {
        #expect(suggest(disposition: #"attachment; filename="notes.md""#, contentType: "application/pdf") == "notes.md")
        #expect(suggest(contentType: "application/pdf", url: "https://a.example/download") == "download.pdf")
        #expect(suggest(contentType: "application/pdf", url: "https://a.example/download.php") == "download.php")
    }
}

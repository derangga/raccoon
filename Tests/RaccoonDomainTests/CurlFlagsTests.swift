import RaccoonDomain
import Testing

struct CurlFlagsTests {
    func collect(_ words: String...) -> CurlFlags {
        CurlFlags.collect(["curl"] + words)
    }

    @Test func `an unknown option is ignored and its value is consumed`() {
        let flags = collect("--retry", "3", "-s", "http://h/", "--compressed")
        #expect(flags.positionals == ["http://h/"])
        #expect(flags.ignoredFlags == ["--retry", "-s", "--compressed"])
        #expect(flags.options.isEmpty)
    }

    @Test func `repeated headers keep their order across -H and --header`() {
        let flags = collect("-H", "a: 1", "--header", "b: 2", "http://h/", "-H", "c: 3")
        #expect(flags.values("header") == ["a: 1", "b: 2", "c: 3"])
    }

    @Test func `short options are read by their long name and switches carry no value`() {
        let flags = collect("-X", "PUT", "-k", "-L", "-G", "-u", "a:b", "-b", "c=1", "-d", "x", "-F", "f=1", "--url", "http://h/")
        #expect(flags.options == [
            .init(name: "request", value: "PUT"),
            .init(name: "insecure", value: nil),
            .init(name: "location", value: nil),
            .init(name: "get", value: nil),
            .init(name: "user", value: "a:b"),
            .init(name: "cookie", value: "c=1"),
            .init(name: "data", value: "x"),
            .init(name: "form", value: "f=1"),
            .init(name: "url", value: "http://h/"),
        ])
        #expect(flags.has("insecure"))
        #expect(!flags.has("digest"))
        #expect(flags.positionals.isEmpty)
    }

    @Test func `data that starts with dashes is the value of its option`() {
        let flags = collect("--data-raw", "------WebKitFormBoundary", "http://h/")
        #expect(flags.values("data-raw") == ["------WebKitFormBoundary"])
        #expect(flags.positionals == ["http://h/"])
    }
}

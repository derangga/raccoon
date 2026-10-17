import RaccoonDomain
import Testing

struct CurlLexerTests {
    @Test(arguments: [
        ("curl http://h/", ["curl", "http://h/"]),
        ("curl -H 'a: b' \"x \\\"y\\\"\" it\\ s", ["curl", "-H", "a: b", "x \"y\"", "it s"]),
        ("curl -d '' x", ["curl", "-d", "", "x"]),
        ("curl -d \"a\\b\" x", ["curl", "-d", "a\\b", "x"]),
        ("curl -d $'it\\'s\\nok' x", ["curl", "-d", "it's\nok", "x"]),
        ("curl -d $'\\x41\\u00e9\\t\\\\' x", ["curl", "-d", "Aé\t\\", "x"]),
        ("curl a\\;b", ["curl", "a;b"]),
        ("curl 'a;b' \"c\nd\"", ["curl", "a;b", "c\nd"]),
        ("curl \\\n  -k \\\r\n  -L \\  \n x", ["curl", "-k", "-L", "x"]),
        ("  curl x\r\n", ["curl", "x"]),
        ("cd /tmp; curl x", ["curl", "x"]),
    ])
    func `commands reads POSIX shell words and keeps the first curl command`(text: String, words: [String]) throws {
        let lexed = try CurlLexer.commands(text)
        #expect(lexed.words == words)
        #expect(lexed.skipped == 0)
    }

    @Test(arguments: [
        ("curl a\ncurl b", ["curl", "a"], 1),
        ("curl a; curl b; curl c", ["curl", "a"], 2),
        ("curl a\r\necho done\r\ncurl b", ["curl", "a"], 1),
    ])
    func `commands counts the other curl commands it skipped`(text: String, words: [String], skipped: Int) throws {
        let lexed = try CurlLexer.commands(text)
        #expect(lexed.words == words)
        #expect(lexed.skipped == skipped)
    }

    @Test(arguments: [
        ("curl -H 'a: b", 9),
        ("curl -d \"a\\\" x", 9),
        ("curl x\ncurl -d $'abc", 16),
        ("curl 'a' 'b", 10),
    ])
    func `an unterminated quote is an error at the opening quote`(text: String, position: Int) {
        #expect(throws: CurlImportError.unterminatedQuote(position: position)) { try CurlLexer.commands(text) }
    }

    @Test(arguments: [
        ("curl http://h/", true),
        ("  \n curl -k x", true),
        ("curl", true),
        ("curly http://h/", false),
        ("http://h/?q=curl", false),
        ("", false),
    ])
    func `isCurl is true when the first word is curl`(text: String, isCurl: Bool) {
        #expect(CurlDetector.isCurl(text) == isCurl)
    }

    @Test(arguments: [
        (["curl", "-fsSL", "x"], ["curl", "-f", "-s", "-S", "-L", "x"]),
        (["curl", "-XPOST", "x"], ["curl", "-X", "POST", "x"]),
        (["curl", "-Ha: b", "x"], ["curl", "-H", "a: b", "x"]),
        (["curl", "-sXPUT", "x"], ["curl", "-s", "-X", "PUT", "x"]),
        (["curl", "-sH", "a: b"], ["curl", "-s", "-H", "a: b"]),
        (["curl", "-d", "-abc", "x"], ["curl", "-d", "-abc", "x"]),
        (["curl", "--data-raw", "-fsSL", "x"], ["curl", "--data-raw", "-fsSL", "x"]),
        (["curl", "--data-raw", "------WebKitFormBoundary", "x"], ["curl", "--data-raw", "------WebKitFormBoundary", "x"]),
        (["curl", "-k", "-", "--retry", "3"], ["curl", "-k", "-", "--retry", "3"]),
    ])
    func `expandShortFlags splits a cluster until a flag that takes a value`(words: [String], expanded: [String]) {
        #expect(CurlLexer.expandShortFlags(words) == expanded)
    }
}

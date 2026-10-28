import Foundation
import RaccoonDomain
import Testing

struct PathVariablesTests {
    /// The token table in editing.md §Path Variables.
    @Test(arguments: [
        ("", []),
        ("http://localhost:3061/posts", []),
        ("localhost:3061/x", []),
        ("{{host}}:8080/x", []),
        ("http://localhost:3061/posts/:id/retry-share-social-media", ["id"]),
        ("/:", []),
        ("/:/x", []),
        ("/:id/:id", ["id"]),
        ("/:id/:other/:id", ["id", "other"]),
        ("http://h/a:id", []),
        ("http://:id", []),
        ("http://h/:{{x}}", []),
        ("http://h/:id{{x}}", ["id"]),
        ("http://h/{{base}}/:id", ["id"]),
        ("http://h/:id.json", ["id"]),
        ("http://h/:id:cancel", ["id"]),
        ("/:user-id", ["user-id"]),
        ("/:user_id", ["user_id"]),
        ("/:ünï", ["ünï"]),
        ("/:Id/:id", ["Id", "id"]),
        ("http://h/a#/:id", []),
        ("http://h/:a#/:b", ["a"]),
        ("/:id", ["id"]),
        ("h/users/:id", ["id"]),
        ("http://h/x://:y", ["y"]),
        ("/:日本/:😀", ["日本"]),
    ] as [(String, [String])])
    func `names reads each :name once, in order, as the token table says`(url: String, names: [String]) {
        #expect(PathVariables.names(in: url) == names)
    }

    @Test func `a token covers the colon and the name in UTF-16 units`() {
        let url = "http://h/:a/😀/:ünï.json"
        let tokens = PathVariables.tokens(in: url)
        #expect(tokens.map(\.name) == ["a", "ünï"])
        let text = url as NSString
        #expect(tokens.map { text.substring(with: $0.range) } == [":a", ":ünï"])
    }

    @Test func `a repeated name has a token each but one name`() {
        #expect(PathVariables.tokens(in: "/:id/:id").count == 2)
        #expect(PathVariables.names(in: "/:id/:id") == ["id"])
    }

    @Test(arguments: [
        ("7", [:], ["id": "7"]),
        ("", ["id": "7"], [:]),
        ("", [:], [:]),
        ("8", ["id": "7", "x": "1"], ["id": "8", "x": "1"]),
    ] as [(String, [String: String], [String: String])])
    func `setValue stores a value, and an empty one removes the key`(text: String, before: [String: String], after: [String: String]) {
        #expect(PathVariables.setValue(text, for: "id", in: before) == after)
    }

    @Test func `setting then clearing a value gives back the same definition`() {
        let old = RequestDefinition.empty
        var edited = old
        edited.pathVariables = PathVariables.setValue("7", for: "id", in: edited.pathVariables)
        #expect(edited != old)
        edited.pathVariables = PathVariables.setValue("", for: "id", in: edited.pathVariables)
        #expect(edited == old)
    }

    @Test(arguments: [
        ("http://h/:id", ["i": "1", "id": "2"], ["id": "2"]),
        ("http://other/:id", ["id": "2"], ["id": "2"]),
        ("http://h/x", ["id": "2"], [:]),
        ("http://h/:a/:b", ["a": "1", "b": "2", "c": "3"], ["a": "1", "b": "2"]),
    ] as [(String, [String: String], [String: String])])
    func `prune drops a value whose name left the URL and keeps the rest`(url: String, values: [String: String], kept: [String: String]) {
        #expect(PathVariables.prune(values, to: url) == kept)
    }

    @Test func `the empty Draft has no Path Variable values`() {
        #expect(RequestDefinition.empty.pathVariables == [:])
    }
}

struct PathEncodingTests {
    @Test(arguments: [
        ("a b", "a%20b"), ("a/b", "a/b"), ("a%2Fb", "a%2Fb"), ("100%", "100%25"),
        ("a?b#c", "a%3Fb%23c"), ("a,b;c=d", "a,b;c=d"), ("José", "Jos%C3%A9"), ("{x}", "%7Bx%7D"),
        ("%", "%25"), ("%4", "%254"), ("%4G", "%254G"), ("%41", "%41"), ("%%41", "%25%41"),
        ("a:b@c&d+e", "a:b@c&d+e"), ("", ""), ("😀", "%F0%9F%98%80"),
        ("a\"b<c>d", "a%22b%3Cc%3Ed"), ("tab\there", "tab%09here"),
    ] as [(String, String)])
    func `segment encodes what a path cannot hold and keeps / and a valid %XX`(value: String, encoded: String) {
        #expect(PathEncoding.segment(value) == encoded)
    }

    @Test(arguments: ["a b?c#d", "line\nbreak", " ", "?#", "x y/z?w#v%"])
    func `the result never holds a space, ? or #`(value: String) {
        let encoded = PathEncoding.segment(value)
        #expect(!encoded.contains(" ") && !encoded.contains("?") && !encoded.contains("#"))
    }
}

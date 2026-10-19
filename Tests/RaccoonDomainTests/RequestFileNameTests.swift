import RaccoonDomain
import Testing

struct RequestFileNameTests {
    static let cases: [(name: String, taken: Set<String>, expected: String)] = [
        ("Create charge", [], "Create charge.json"),
        ("a/b:c", [], "a-b-c.json"),
        ("Refund", ["Refund.json"], "Refund 2.json"),
        ("Refund", ["refund.json", "Refund 2.json"], "Refund 3.json"),
        ("注文 / 返金", [], "注文 - 返金.json"),
        (".env check", [], "-env check.json"),
    ]

    @Test(arguments: cases)
    func `a Request's file name is its name, sanitised, with 2 on a clash`(name: String, taken: Set<String>, expected: String) {
        #expect(RequestFileName.make(name, taken: taken) == expected)
    }
}

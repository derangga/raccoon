import RaccoonDomain
import Testing

struct AuthNoteTests {
    static let instead = " An enabled Authorization row in Headers is sent instead."
    static let none = "No Authorization header is added."
    static let basic = "The Authorization header is generated from the username and password when you send the request."
    static let bearer = "The Authorization header is sent as Bearer followed by the token."

    static let schemes: [(Auth, String)] = [
        (.none, none), (.basic(user: "a", password: "b"), basic), (.bearer(token: "t"), bearer),
    ]

    @Test(arguments: schemes)
    func `a scheme says what the send does`(auth: Auth, sentence: String) {
        #expect(AuthNote.text(auth, headers: []) == sentence)
        #expect(AuthNote.text(auth, headers: [Row(name: "Accept", value: "*/*")]) == sentence)
    }

    static let withRow: [(Auth, String, Row)] = schemes.flatMap { auth, sentence in
        [Row(name: "Authorization", value: "Basic eHl6"), Row(name: "authorization", value: "x"), Row(name: "AUTHORIZATION", value: "")]
            .map { (auth, sentence, $0) }
    }

    @Test(arguments: withRow)
    func `an enabled Authorization row adds that it is sent instead, except for None`(auth: Auth, sentence: String, row: Row) {
        let expected = auth == .none ? sentence : sentence + Self.instead
        #expect(AuthNote.text(auth, headers: [Row(name: "Accept", value: ""), row]) == expected)
    }

    @Test(arguments: schemes)
    func `a Disabled Authorization row does not count`(auth: Auth, sentence: String) {
        #expect(AuthNote.text(auth, headers: [Row(name: "Authorization", value: "x", isEnabled: false)]) == sentence)
    }
}

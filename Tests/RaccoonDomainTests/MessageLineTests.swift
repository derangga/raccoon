import RaccoonDomain
import Testing

struct MessageLineTests {
    let error = MessageLine.error("No URL in this curl command.")
    let note = MessageLine.note("Ignored: --retry, -s")

    @Test func `a note goes away on the next URL edit, an error stays`() {
        #expect(note.afterURLEdit == nil)
        #expect(error.afterURLEdit == error)
    }

    @Test func `an error goes away on the next send or paste, a note stays`() {
        #expect(error.afterSendOrPaste == nil)
        #expect(note.afterSendOrPaste == note)
    }

    @Test(arguments: [
        ("GET", ColorToken.methodGet), ("POST", .methodPost), ("PUT", .methodPut), ("PATCH", .methodPatch),
        ("DELETE", .methodDelete), ("HEAD", .methodHead), ("OPTIONS", .methodOptions),
        ("PROPFIND", .methodOther), ("PURGE", .methodOther),
    ])
    func `each method has its color, and any other method shares one`(method: String, token: ColorToken) {
        #expect(ColorToken.method(method) == token)
    }
}

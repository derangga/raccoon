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

    static let undefined: [([String], String?, String)] = [
        (["a"], "Staging", "Not sent. a is not defined in Staging or in Globals."),
        (["charge_id", "tenant_id"], "Staging", "Not sent. charge_id and tenant_id are not defined in Staging or in Globals."),
        (["a", "b", "c"], nil, "Not sent. a, b and c are not defined in Globals."),
    ]

    @Test(arguments: undefined)
    func `a blocked send names every missing Variable and where it looked`(names: [String], environment: String?, text: String) {
        #expect(MessageLine.undefined(names.map { VariableName($0)! }, in: environment) == .error(text))
    }
}

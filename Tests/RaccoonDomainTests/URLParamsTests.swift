import RaccoonDomain
import Testing

struct URLParamsTests {
    func row(_ name: String, _ value: String, enabled: Bool = true) -> Row {
        Row(name: name, value: value, isEnabled: enabled)
    }

    @Test(arguments: [
        ("http://h/search?q=a%20b", "http://h/search", [Row(name: "q", value: "a b")]),
        ("http://h/?token=abc==", "http://h/", [Row(name: "token", value: "abc==")]),
        ("http://h/?id={{user_id}}", "http://h/", [Row(name: "id", value: "{{user_id}}")]),
        ("http://h/?q={{a%20b}}x%20y", "http://h/", [Row(name: "q", value: "{{a%20b}}x y")]),
        ("http://h/?flag&a=1&&b=", "http://h/", [Row(name: "flag", value: ""), Row(name: "a", value: "1"), Row(name: "b", value: "")]),
        ("http://h/?q=a+b?c", "http://h/", [Row(name: "q", value: "a+b?c")]),
        ("http://h/", "http://h/", []),
    ])
    func `split takes the base at the first ? and decoded pairs at & and the first =`(text: String, base: String, pairs: [Row]) {
        let split = URLText.split(text)
        #expect(split.base == base)
        #expect(split.pairs == pairs)
    }

    @Test(arguments: [
        "http://h/",
        "http://h/search?q=a%20b",
        "http://h/?token=abc==",
        "http://h/?id={{user_id}}&x=1",
        "https://api.example.com/v1/users?page=2&sort=name",
        "http://h/?q=a+b",
        "http://h/?flag=",
        "http://h/?a%26b=c%26d&e%3Df=g",
    ])
    func `join renders exactly what split read`(text: String) {
        let split = URLText.split(text)
        #expect(URLText.join(split.base, params: split.pairs) == text)
    }

    @Test func `join skips Disabled Rows and leaves {{name}} unencoded`() {
        let params = [row("off", "x", enabled: false), row("id", "{{user id}}"), row("q", "a b#c")]
        #expect(URLText.join("http://h/", params: params) == "http://h/?id={{user id}}&q=a%20b%23c")
    }

    @Test(arguments: [
        ([Row(name: "a", value: "1"), Row(name: "B", value: "2", isEnabled: false), Row(name: "c", value: "3")],
         [Row(name: "a", value: "1"), Row(name: "c", value: "4")],
         [Row(name: "a", value: "1"), Row(name: "B", value: "2", isEnabled: false), Row(name: "c", value: "4")]),
        ([Row(name: "B", value: "2", isEnabled: false), Row(name: "a", value: "1")],
         [Row(name: "x", value: "9"), Row(name: "y", value: "8")],
         [Row(name: "B", value: "2", isEnabled: false), Row(name: "x", value: "9"), Row(name: "y", value: "8")]),
        ([Row(name: "a", value: "1"), Row(name: "b", value: "2"), Row(name: "C", value: "3", isEnabled: false)],
         [],
         [Row(name: "C", value: "3", isEnabled: false)]),
        ([Row(name: "a", value: "1"), Row(name: "B", value: "2", isEnabled: false)],
         [Row(name: "a", value: "1"), Row(name: "n", value: "5"), Row(name: "m", value: "6")],
         [Row(name: "a", value: "1"), Row(name: "B", value: "2", isEnabled: false), Row(name: "n", value: "5"), Row(name: "m", value: "6")]),
    ])
    func `typing replaces the enabled rows and keeps Disabled Rows at their index`(params: [Row], typed: [Row], merged: [Row]) {
        #expect(Params.merge(typed, into: params) == merged)
    }
}

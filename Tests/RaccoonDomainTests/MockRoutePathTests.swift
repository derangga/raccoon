import RaccoonDomain
import Testing

/// The path text the Mock Server sheet shows for a Request's URL.
struct MockRoutePathTests {
    @Test(arguments: [
        ("https://api.example.com/users/:id", "/users/:id"),
        ("http://localhost:3000/users", "/users"),
        ("{{baseUrl}}/users/:id", "/users/:id"),
        ("{{host}}/v1/{{version}}/items", "/v1/{{version}}/items"),
        ("{{scheme}}://{{host}}/users", "/users"),
        ("https://api.example.com", "/"),
        ("{{baseUrl}}", "/"),
        ("{{baseUrl}}/", "/"),
        ("", "/"),
        ("https://api.example.com/users/", "/users"),
        ("https://api.example.com/users?page=2&x=/a/b", "/users"),
        ("https://h/a%20b/x", "/a%20b/x"),
        ("/users/me", "/users/me"),
    ])
    func `path of a URL drops the scheme, authority and query and keeps the rest as typed`(url: String, expected: String) {
        #expect(MockRoutes.path(of: url) == expected)
    }
}

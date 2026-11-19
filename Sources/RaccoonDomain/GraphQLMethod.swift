/// A GraphQL body is sent as a POST: a GET or HEAD cannot carry it (environment-facts.md).
public enum GraphQLMethod {
    /// Methods are stored uppercased; the comparison ignores case anyway.
    public static func forPick(_ method: String) -> String {
        switch method.uppercased() {
        case "GET", "HEAD": "POST"
        default: method
        }
    }
}

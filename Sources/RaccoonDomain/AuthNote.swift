import Foundation

extension Row {
    /// An enabled row named `Authorization`, in any case and with any value, empty too. It is
    /// sent instead of Auth's header; a Disabled Row neither wins nor blocks Auth. The resolver
    /// and the Auth pane's paragraph both ask this.
    public var winsOverAuth: Bool {
        isEnabled && name.caseInsensitiveCompare("Authorization") == .orderedSame
    }
}

/// The paragraph under the Auth type pop-up: what the send does.
public enum AuthNote {
    public static func text(_ auth: Auth, headers: [Row]) -> String {
        let sentence: String
        switch auth {
        case .none: return "No Authorization header is added."
        case .basic: sentence = "The Authorization header is generated from the username and password when you send the request."
        case .bearer: sentence = "The Authorization header is sent as Bearer followed by the token."
        }
        return headers.contains(where: \.winsOverAuth) ? sentence + " An enabled Authorization row in Headers is sent instead." : sentence
    }
}

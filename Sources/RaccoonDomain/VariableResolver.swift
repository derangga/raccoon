import Foundation

/// The only way to a ResolvedRequest. For now it builds the URL from the URL text as typed;
/// params, Disabled Rows, Auth and Variable substitution grow here.
public enum VariableResolver {
    public static func resolve(_ definition: RequestDefinition) throws(ResolveError) -> ResolvedRequest {
        guard let url = URL(string: definition.url), url.scheme != nil, url.host() != nil else {
            throw .invalidURL(definition.url)
        }
        return ResolvedRequest(definition: definition, url: url)
    }
}

import Foundation

/// The URL bar's text ↔ `url` and the Params table. The table is the source of truth for the
/// query; the bar shows `url` plus the enabled params.
public enum URLText {
    /// The base before the first `?`, and the query's pairs: split at `&`, name and value at the
    /// first `=`, decoded except inside `{{…}}`. Empty pairs are skipped.
    public static func split(_ text: String) -> (base: String, pairs: [Row]) {
        guard let mark = text.firstIndex(of: "?") else { return (text, []) }
        let pairs = text[text.index(after: mark)...].split(separator: "&").map { pair in
            let (name, value) = pair.firstIndex(of: "=").map { (pair[..<$0], pair[pair.index(after: $0)...]) } ?? (pair[...], "")
            return Row(name: decoded(name), value: decoded(value))
        }
        return (String(text[..<mark]), pairs)
    }

    /// The text the URL bar shows: `base`, then the enabled params encoded as the resolver
    /// sends them, with `{{…}}` left as typed.
    public static func join(_ base: String, params: [Row]) -> String {
        let enabled = params.filter(\.isEnabled)
        guard !enabled.isEmpty else { return base }
        let query = enabled.map {
            outsideVariables($0.name) { QueryEncoding.name($0) } + "=" + outsideVariables($0.value) { QueryEncoding.value($0) }
        }
        return base + "?" + query.joined(separator: "&")
    }

    private static func decoded(_ text: Substring) -> String {
        outsideVariables(text) { $0.removingPercentEncoding ?? String($0) }
    }

    /// Applies `transform` to every stretch of `text` that is not a `{{…}}` reference.
    private static func outsideVariables(_ text: some StringProtocol, _ transform: (Substring) -> String) -> String {
        let text = Substring(text)
        var result = ""
        var rest = text.startIndex
        for match in text.matches(of: /\{\{[^{}]*\}\}/) {
            result += transform(text[rest..<match.range.lowerBound]) + match.output
            rest = match.range.upperBound
        }
        return result + transform(text[rest...])
    }
}

public enum Params {
    /// The typed pairs replace the enabled rows, in order. Disabled Rows are not in the text, so
    /// they stay at their old index; one past the new end goes after the typed pairs.
    public static func merge(_ pairs: [Row], into params: [Row]) -> [Row] {
        var slots = [Row?](repeating: nil, count: pairs.count + params.count { !$0.isEnabled })
        var overflow: [Row] = []
        for (index, row) in params.enumerated() where !row.isEnabled {
            if index < slots.count { slots[index] = row } else { overflow.append(row) }
        }
        var fill = (pairs + overflow).makeIterator()
        return slots.map { $0 ?? fill.next()! }
    }
}

/// One encoding for the URL bar and the wire: only what a query cannot hold, plus `&`, and `=` in
/// a name. `+` stays `+`, as curl and Postman send it.
enum QueryEncoding {
    private static let valueAllowed = CharacterSet.urlQueryAllowed.subtracting(CharacterSet(charactersIn: "&"))
    private static let nameAllowed = valueAllowed.subtracting(CharacterSet(charactersIn: "="))

    static func value(_ text: some StringProtocol) -> String {
        text.addingPercentEncoding(withAllowedCharacters: valueAllowed) ?? String(text)
    }

    static func name(_ text: some StringProtocol) -> String {
        text.addingPercentEncoding(withAllowedCharacters: nameAllowed) ?? String(text)
    }
}

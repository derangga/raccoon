import Foundation
import UniformTypeIdentifiers

/// The name Save Response Body offers. The server and the URL are untrusted: a name that could
/// leave the folder the user picked is skipped for the next source.
public enum ResponseFileName {
    /// `Content-Disposition` `filename*` (RFC 8187), then `filename`, then the last path
    /// component of `url`, then "response". A name with no extension gets the one the
    /// `Content-Type` prefers, when it has one.
    public static func suggest(headers: [Response.Header], url: URL?) -> String {
        let disposition = headers.first { $0.name.lowercased() == "content-disposition" }.map { parameters($0.value) } ?? [:]
        let candidates = [disposition["filename*"].flatMap(extended), disposition["filename"], url?.lastPathComponent]
        let name = candidates.compactMap { $0 }.first(where: isSafe) ?? "response"
        guard (name as NSString).pathExtension.isEmpty,
              let type = headers.first(where: { $0.name.lowercased() == "content-type" })?.value
                  .split(separator: ";").first?.trimmingCharacters(in: .whitespaces),
              let ext = UTType(mimeType: type.lowercased())?.preferredFilenameExtension
        else { return name }
        return name + "." + ext
    }

    private static func isSafe(_ name: String) -> Bool {
        !name.isEmpty && name != "." && name != ".."
            && !name.unicodeScalars.contains { $0 == "/" || $0 == ":" || $0.properties.generalCategory == .control }
    }

    /// `charset'language'percent-encoded`. Only UTF-8 is read: a name in another charset is
    /// left to `filename`.
    private static func extended(_ value: String) -> String? {
        let parts = value.split(separator: "'", maxSplits: 2, omittingEmptySubsequences: false)
        guard parts.count == 3, parts[0].lowercased() == "utf-8" else { return nil }
        return String(parts[2]).removingPercentEncoding
    }

    /// The parameters after the disposition type, by lowercased name, quotes removed. A `;`
    /// inside quotes does not split.
    private static func parameters(_ header: String) -> [String: String] {
        var segments = [""]
        var quoted = false
        var escaped = false
        for character in header {
            if quoted, escaped {
                escaped = false
            } else if quoted, character == "\\" {
                escaped = true
            } else if character == "\"" {
                quoted.toggle()
            } else if character == ";", !quoted {
                segments.append("")
                continue
            }
            segments[segments.count - 1].append(character)
        }
        var result: [String: String] = [:]
        for segment in segments.dropFirst() {
            guard let equals = segment.firstIndex(of: "=") else { continue }
            let name = segment[..<equals].trimmingCharacters(in: .whitespaces).lowercased()
            let value = segment[segment.index(after: equals)...].trimmingCharacters(in: .whitespaces)
            // The first of a repeated name wins.
            if result[name] == nil { result[name] = unquoted(value) }
        }
        return result
    }

    private static func unquoted(_ value: String) -> String {
        guard value.count >= 2, value.hasPrefix("\""), value.hasSuffix("\"") else { return value }
        var out = ""
        var escaped = false
        for character in value.dropFirst().dropLast() {
            if !escaped, character == "\\" { escaped = true; continue }
            escaped = false
            out.append(character)
        }
        return out
    }
}

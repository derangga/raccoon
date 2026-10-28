import Foundation

/// One Path Variable in a URL: the range covers the `:` and the name, in UTF-16 units as text
/// storage takes it.
public struct PathVariableToken: Equatable, Sendable {
    public var range: NSRange
    public var name: String

    public init(range: NSRange, name: String) {
        self.range = range
        self.name = name
    }
}

/// The `:name` segments of a URL and the values a Request keeps for them (editing.md §Path
/// Variables). The URL text is the source of truth for which names exist; the values only follow it.
public enum PathVariables {
    /// Every `:name` in `url`, in text order. Scanning starts at the first `/` that is not part of
    /// `://`, so the authority is never read, and stops at the first `#`. No `{{name}}` is skipped
    /// on purpose: a Variable has no `/`, `:` or name character in it, so it can neither start a
    /// token nor sit inside one.
    public static func tokens(in url: String) -> [PathVariableToken] {
        let units = Array(url.utf16)
        let slash: UInt16 = 0x2F, colon: UInt16 = 0x3A, hash: UInt16 = 0x23
        let end = units.firstIndex(of: hash) ?? units.count
        guard var i = units[..<end].indices.first(where: { index in
            units[index] == slash
                && !(index > 0 && units[index - 1] == colon && index + 1 < end && units[index + 1] == slash)
                && !(index > 1 && units[index - 1] == slash && units[index - 2] == colon)
        }) else { return [] }
        var tokens: [PathVariableToken] = []
        while i + 1 < end {
            guard units[i] == slash, units[i + 1] == colon else { i += 1; continue }
            var j = i + 2
            while j < end, let width = nameUnits(units, at: j, end: end) { j += width }
            if j > i + 2 {
                let name = String(decoding: units[(i + 2)..<j], as: UTF16.self)
                tokens.append(PathVariableToken(range: NSRange(location: i + 1, length: j - i - 1), name: name))
            }
            i = max(j, i + 1)
        }
        return tokens
    }

    /// The names, first appearance order, each once.
    public static func names(in url: String) -> [String] {
        var seen: Set<String> = []
        return tokens(in: url).map(\.name).filter { seen.insert($0).inserted }
    }

    /// Only the values whose name is still in `url`: a name that leaves the URL loses its value.
    public static func prune(_ values: [String: String], to url: String) -> [String: String] {
        let names = Set(names(in: url))
        return values.filter { names.contains($0.key) }
    }

    /// The values of the names `url` has, in URL order: what a send substitutes. A value for a name
    /// the URL lacks is not sent, so nothing reads it.
    public static func sentValues(_ values: [String: String], in url: String) -> [String] {
        names(in: url).compactMap { values[$0] }
    }

    /// `""` removes the key, so a typed-then-cleared value gives back an equal definition.
    public static func setValue(_ text: String, for name: String, in values: [String: String]) -> [String: String] {
        var values = values
        values[name] = text.isEmpty ? nil : text
        return values
    }

    /// The width in UTF-16 units of the name character at `i`, or nil when it is not one: letters,
    /// marks and digits of any script, `_` and `-`.
    private static func nameUnits(_ units: [UInt16], at i: Int, end: Int) -> Int? {
        let unit = units[i]
        if unit == 0x5F || unit == 0x2D { return 1 }
        var width = 1
        var value = UInt32(unit)
        if UTF16.isLeadSurrogate(unit), i + 1 < end, UTF16.isTrailSurrogate(units[i + 1]) {
            value = 0x10000 + ((value - 0xD800) << 10) + (UInt32(units[i + 1]) - 0xDC00)
            width = 2
        }
        guard let scalar = Unicode.Scalar(value), CharacterSet.alphanumerics.contains(scalar) else { return nil }
        return width
    }
}

/// What a Path Variable's value becomes in the path (sending.md): the way Postman encodes it.
public enum PathEncoding {
    /// Percent-encodes the UTF-8 of every character `urlPathAllowed` does not allow. `/` stays,
    /// and so does a `%` that starts `%XX`: any other `%` becomes `%25`.
    public static func segment(_ value: String) -> String {
        let scalars = Array(value.unicodeScalars)
        var result = ""
        for (index, scalar) in scalars.enumerated() {
            if scalar == "%", index + 2 < scalars.count, scalars[index + 1].properties.isASCIIHexDigit, scalars[index + 2].properties.isASCIIHexDigit {
                result.unicodeScalars.append(scalar)
            } else if CharacterSet.urlPathAllowed.contains(scalar) {
                result.unicodeScalars.append(scalar)
            } else {
                for byte in String(scalar).utf8 { result += String(format: "%%%02X", byte) }
            }
        }
        return result
    }
}

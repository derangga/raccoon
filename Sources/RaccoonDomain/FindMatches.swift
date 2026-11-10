import Foundation

/// The Find panel's matches in a body: case-insensitive and literal, overlapping, in the UTF-16
/// offsets NSString counts, so they map straight onto the text view.
public struct FindMatches: Equatable, Sendable {
    /// A one-letter query on a 5 MB body finds a million; past this many the count reads "+".
    public static let cap = 10_000

    public let query: String
    /// In text order. Every match has the query's length, so upper bounds are in order too.
    public let ranges: [Range<Int>]
    /// More matches exist past the last of `ranges`.
    public let capped: Bool

    public init(of query: String, in text: NSString, cap: Int = FindMatches.cap) {
        var ranges: [Range<Int>] = []
        var capped = false
        var start = 0
        while !query.isEmpty, start < text.length {
            let found = text.range(of: query, options: [.caseInsensitive, .literal],
                                   range: NSRange(location: start, length: text.length - start))
            guard found.location != NSNotFound else { break }
            guard ranges.count < cap else {
                capped = true
                break
            }
            ranges.append(found.location ..< NSMaxRange(found))
            start = found.location + 1
        }
        self.query = query
        self.ranges = ranges
        self.capped = capped
    }

    /// Where the panel starts: the first match starting at or after `offset`, wrapping to the first.
    public func first(atOrAfter offset: Int) -> Int? {
        guard !ranges.isEmpty else { return nil }
        let index = Self.firstIndex(in: ranges) { $0.lowerBound >= offset }
        return index == ranges.count ? 0 : index
    }

    /// Next or previous, wrapping past either end.
    public func step(_ current: Int, forward: Bool) -> Int {
        (current + (forward ? 1 : -1) + ranges.count) % ranges.count
    }

    /// "2 of 7", "2 of 10,000+", "No results"; empty while the field is.
    public func count(current: Int?) -> String {
        if query.isEmpty { return "" }
        guard let current, !ranges.isEmpty else { return "No results" }
        return "\(Self.grouped(current + 1)) of \(Self.grouped(ranges.count))\(capped ? "+" : "")"
    }

    /// The indices of the matches that overlap `range`, for highlighting what is on screen only.
    public func indices(overlapping range: Range<Int>) -> Range<Int> {
        let low = Self.firstIndex(in: ranges) { $0.upperBound > range.lowerBound }
        let high = Self.firstIndex(in: ranges) { $0.lowerBound >= range.upperBound }
        return low ..< max(low, high)
    }

    /// The first index where `isPast` holds, which must be false then true along `ranges`.
    private static func firstIndex(in ranges: [Range<Int>], where isPast: (Range<Int>) -> Bool) -> Int {
        var (low, high) = (0, ranges.count)
        while low < high {
            let mid = (low + high) / 2
            if isPast(ranges[mid]) { high = mid } else { low = mid + 1 }
        }
        return low
    }

    /// "10,000": fixed separators, so the count reads the same in every locale, as the status line does.
    private static func grouped(_ number: Int) -> String {
        let digits = Array(String(number))
        return digits.enumerated().map { index, digit in
            index > 0 && (digits.count - index) % 3 == 0 ? ",\(digit)" : "\(digit)"
        }.joined()
    }
}

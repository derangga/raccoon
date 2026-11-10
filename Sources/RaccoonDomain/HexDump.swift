import Foundation

/// The Hex view's text: `hexdump -C` run on the first `limit` bytes, byte for byte, with two
/// differences. Repeated lines are never collapsed to `*`, because the offset column is the
/// line's address and every line is shown. And the last line has no newline after it, so the
/// text view does not end on an empty line. Like hexdump, it ends with the offset after the last
/// shown byte, and empty data dumps to nothing.
public struct HexDump: Equatable, Sendable {
    /// 1 MB, in the 1000-based units of `ResponseBody.prettyThreshold`: 62,500 lines.
    public static let limit = 1_000_000

    public let text: String
    public let shownBytes: Int
    public let totalBytes: Int

    public init(_ data: Data, limit: Int = HexDump.limit) {
        let shown = min(data.count, limit)
        totalBytes = data.count
        shownBytes = shown
        guard shown > 0 else {
            text = ""
            return
        }
        let digits = Array("0123456789abcdef".utf8)
        var out = [UInt8]()
        // 78 characters and a newline a line, and the final offset.
        out.reserveCapacity((shown + 15) / 16 * 79 + 9)
        func offset(_ value: Int) {
            for shift in stride(from: 28, through: 0, by: -4) { out.append(digits[value >> shift & 0xF]) }
        }
        data.withUnsafeBytes { (bytes: UnsafeRawBufferPointer) in
            for start in stride(from: 0, to: shown, by: 16) {
                let line = bytes[start ..< min(start + 16, shown)]
                offset(start)
                out.append(contentsOf: [0x20, 0x20])
                for column in 0 ..< 16 {
                    if column == 8 { out.append(0x20) }
                    if column < line.count {
                        let byte = line[start + column]
                        out.append(contentsOf: [digits[Int(byte >> 4)], digits[Int(byte & 0xF)]])
                    } else {
                        out.append(contentsOf: [0x20, 0x20])
                    }
                    if column < 15 { out.append(0x20) }
                }
                out.append(contentsOf: [0x20, 0x20, 0x7C])
                out.append(contentsOf: line.map { 0x20 ... 0x7E ~= $0 ? $0 : 0x2E })
                out.append(contentsOf: [0x7C, 0x0A])
            }
        }
        offset(shown)
        text = String(decoding: out, as: UTF8.self)
    }
}

import Foundation
import RaccoonDomain
import Testing

/// Every expected text below is `hexdump -C` run in a shell on the same bytes, with its `*` line
/// collapsing undone and no newline after the last line.
struct HexDumpTests {
    @Test func `no bytes dump to nothing, as hexdump -C does`() {
        let dump = HexDump(Data())
        #expect(dump.text == "")
        #expect(dump.shownBytes == 0)
        #expect(dump.totalBytes == 0)
    }

    @Test func `one byte pads the hex columns so the ASCII column still lines up`() {
        let dump = HexDump(Data("A".utf8))
        #expect(dump.text == """
        00000000  41                                                |A|
        00000001
        """)
    }

    @Test func `exactly 16 bytes is one full line and the final offset`() {
        #expect(HexDump(Data("0123456789abcdef".utf8)).text == """
        00000000  30 31 32 33 34 35 36 37  38 39 61 62 63 64 65 66  |0123456789abcdef|
        00000010
        """)
    }

    @Test func `17 bytes spill one byte onto a second line`() {
        #expect(HexDump(Data("0123456789abcdefg".utf8)).text == """
        00000000  30 31 32 33 34 35 36 37  38 39 61 62 63 64 65 66  |0123456789abcdef|
        00000010  67                                                |g|
        00000011
        """)
    }

    @Test func `a byte outside 0x20 to 0x7E is a dot, and the boundaries are kept`() {
        #expect(HexDump(Data([0x61, 0x00, 0x1F, 0x7F, 0x80, 0xFF, 0x7A, 0x20, 0x7E])).text == """
        00000000  61 00 1f 7f 80 ff 7a 20  7e                       |a.....z ~|
        00000009
        """)
    }

    @Test func `a second line shorter than a group still lines up`() {
        #expect(HexDump(Data("abcdefghijklmnopqrst".utf8)).text == """
        00000000  61 62 63 64 65 66 67 68  69 6a 6b 6c 6d 6e 6f 70  |abcdefghijklmnop|
        00000010  71 72 73 74                                       |qrst|
        00000014
        """)
    }

    @Test func `repeated lines are all shown, never collapsed to a star`() {
        let dump = HexDump(Data(repeating: 0x61, count: 48))
        #expect(dump.text == """
        00000000  61 61 61 61 61 61 61 61  61 61 61 61 61 61 61 61  |aaaaaaaaaaaaaaaa|
        00000010  61 61 61 61 61 61 61 61  61 61 61 61 61 61 61 61  |aaaaaaaaaaaaaaaa|
        00000020  61 61 61 61 61 61 61 61  61 61 61 61 61 61 61 61  |aaaaaaaaaaaaaaaa|
        00000030
        """)
    }

    @Test func `one byte past the limit is cut at the limit and the totals say so`() {
        let dump = HexDump(Data("abcdefghijklmnopqrst".utf8), limit: 12)
        #expect(dump.text == """
        00000000  61 62 63 64 65 66 67 68  69 6a 6b 6c              |abcdefghijkl|
        0000000c
        """)
        #expect(dump.shownBytes == 12)
        #expect(dump.totalBytes == 20)
        let over = HexDump(Data("0123456789abcdefg".utf8), limit: 16)
        #expect(over.text == HexDump(Data("0123456789abcdef".utf8)).text)
        #expect(over.shownBytes == 16)
        #expect(over.totalBytes == 17)
    }

    @Test func `the limit is 1 MB in the 1000-based units of the Pretty threshold`() {
        #expect(HexDump.limit == 1_000_000)
        #expect(HexDump(Data(repeating: 0, count: 1_000_001)).shownBytes == 1_000_000)
    }
}

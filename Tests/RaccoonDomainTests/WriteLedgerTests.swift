import Foundation
import RaccoonDomain
import Testing

struct WriteLedgerTests {
    static let written = Data(#"{"version": 1}"#.utf8)

    @Test func `the bytes Raccoon wrote are ours`() {
        var ledger = WriteLedger()
        ledger.record("Payments API/Create charge.json", Self.written)
        #expect(ledger.isOurs("Payments API/Create charge.json", Self.written))
    }

    @Test func `changed bytes, or a path never written, are not ours`() {
        var ledger = WriteLedger()
        ledger.record("Payments API/Create charge.json", Self.written)
        #expect(!ledger.isOurs("Payments API/Create charge.json", Data(#"{"version": 1, "x": 2}"#.utf8)))
        #expect(!ledger.isOurs("Payments API/Refund.json", Self.written))
    }

    @Test func `identical bytes written by someone else, as by a git checkout, are ours`() {
        var ledger = WriteLedger()
        ledger.record("a.json", Self.written)
        let checkedOut = Data(String(decoding: Self.written, as: UTF8.self).utf8)
        #expect(ledger.isOurs("a.json", checkedOut))
    }
}

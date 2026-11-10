import Foundation
import Testing

@testable import RaccoonDomain

struct TimingTests {
    static let t0 = Date(timeIntervalSince1970: 1_000)

    /// A mark `ms` milliseconds after the fetch started.
    static func at(_ ms: Int) -> Date { t0.addingTimeInterval(Double(ms) / 1_000) }

    /// A full TLS send: DNS 4, Connect 12 (the TCP handshake, up to where TLS starts), TLS 18,
    /// Send 0, Waiting 10, Download 1, 47 in all.
    static func full() -> Timing.Marks {
        var marks = Timing.Marks()
        marks.fetchStart = at(0)
        marks.domainLookupStart = at(2)
        marks.domainLookupEnd = at(6)
        marks.connectStart = at(6)
        marks.secureConnectionStart = at(18)
        marks.secureConnectionEnd = at(36)
        marks.connectEnd = at(36)
        marks.requestStart = at(36)
        marks.requestEnd = at(36)
        marks.responseStart = at(46)
        marks.responseEnd = at(47)
        marks.protocolName = "h2"
        marks.remoteAddress = "93.184.216.34"
        marks.remotePort = 443
        marks.tlsVersion = 0x0304
        marks.bodyBytesOnWire = 420
        return marks
    }

    @Test func `every mark gives every phase`() {
        let timing = Timing(Self.full())

        #expect(timing.dns == .milliseconds(4))
        #expect(timing.connect == .milliseconds(12))
        #expect(timing.tls == .milliseconds(18))
        #expect(timing.send == .zero)
        #expect(timing.waiting == .milliseconds(10))
        #expect(timing.download == .milliseconds(1))
        #expect(timing.total == .milliseconds(47))
        #expect(!timing.reusedConnection)
        #expect(timing.protocolName == "h2")
        #expect(timing.remoteAddress == "93.184.216.34:443")
        #expect(timing.tlsVersion == "TLS 1.3")
        #expect(timing.bodyBytesOnWire == 420)
    }

    @Test func `a reused connection has no DNS, Connect or TLS, not zero`() {
        var marks = Self.full()
        marks.reusedConnection = true
        for keyPath: WritableKeyPath<Timing.Marks, Date?> in [
            \.domainLookupStart, \.domainLookupEnd, \.connectStart, \.connectEnd, \.secureConnectionStart, \.secureConnectionEnd,
        ] { marks[keyPath: keyPath] = nil }
        let timing = Timing(marks)

        #expect(timing.reusedConnection)
        #expect(timing.dns == nil)
        #expect(timing.connect == nil)
        #expect(timing.tls == nil)
        #expect(timing.waiting == .milliseconds(10))
        #expect(timing.total == .milliseconds(47))
    }

    @Test func `plain HTTP has no TLS and Connect runs to connectEnd`() {
        var marks = Self.full()
        marks.secureConnectionStart = nil
        marks.secureConnectionEnd = nil
        marks.connectEnd = Self.at(14)
        marks.tlsVersion = nil
        let timing = Timing(marks)

        #expect(timing.tls == nil)
        #expect(timing.connect == .milliseconds(8))
        #expect(timing.tlsVersion == nil)
    }

    @Test func `an end before its start gives nil for that phase, never a negative one`() {
        var marks = Self.full()
        marks.domainLookupEnd = Self.at(0)
        marks.responseEnd = Self.at(40)
        marks.fetchStart = Self.at(50)
        let timing = Timing(marks)

        #expect(timing.dns == nil)
        #expect(timing.download == nil)
        #expect(timing.total == nil)
        #expect(timing.connect == .milliseconds(12))
    }

    @Test func `a missing mark gives nil for the phases that use it and no others`() {
        var marks = Self.full()
        marks.requestEnd = nil
        let timing = Timing(marks)

        #expect(timing.send == nil)
        #expect(timing.waiting == nil)
        #expect(timing.download == .milliseconds(1))
        #expect(Timing(Timing.Marks()) == Timing())
    }

    @Test(arguments: [
        (nil, 443, nil), ("10.0.0.1", nil, "10.0.0.1"), ("10.0.0.1", 8080, "10.0.0.1:8080"), ("::1", 443, "[::1]:443"),
    ] as [(String?, Int?, String?)])
    func `the address carries its port when known, an IPv6 one in brackets`(address: String?, port: Int?, expected: String?) {
        var marks = Timing.Marks()
        marks.remoteAddress = address
        marks.remotePort = port

        #expect(Timing(marks).remoteAddress == expected)
    }

    @Test(arguments: [
        (UInt16(0x0304), "TLS 1.3"), (0x0303, "TLS 1.2"), (0x0302, "TLS 1.1"), (0x0301, "TLS 1.0"),
    ] as [(UInt16, String)])
    func `a TLS wire version is named`(raw: UInt16, name: String) {
        var marks = Timing.Marks()
        marks.tlsVersion = raw

        #expect(Timing(marks).tlsVersion == name)
    }

    @Test func `a TLS version nobody named is left out`() {
        var marks = Timing.Marks()
        marks.tlsVersion = 0x0100

        #expect(Timing(marks).tlsVersion == nil)
    }

    // MARK: pairing

    func timing(_ ms: Int) -> Timing { Timing(total: .milliseconds(ms)) }

    @Test func `as many timings as requests pair one to one`() {
        #expect(Timing.paired([timing(1), timing(2)], requests: 2) == [timing(1), timing(2)])
    }

    @Test func `fewer timings than requests pair from the end`() {
        #expect(Timing.paired([timing(2)], requests: 3) == [nil, nil, timing(2)])
        #expect(Timing.paired([], requests: 2) == [nil, nil])
    }

    @Test func `more timings than requests leave every Timing nil`() {
        #expect(Timing.paired([timing(1), timing(2), timing(3)], requests: 2) == [nil, nil])
    }

    @Test func `the metrics' 20 transactions for 21 requests leave the first nil`() {
        let kept = (1...20).map(timing)
        let paired = Timing.paired(kept, requests: 21)

        #expect(paired.count == 21)
        #expect(paired[0] == nil)
        #expect(Array(paired.dropFirst()) == kept)
    }
}

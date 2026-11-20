import RaccoonDomain
import Testing

struct MockPortTests {
    @Test(arguments: [
        ("", MockPort.automatic),
        ("   ", .automatic),
        ("\n", .automatic),
        ("1024", .port(1024)),
        ("65535", .port(65535)),
        ("3000", .port(3000)),
        ("  3000  ", .port(3000)),
        ("03000", .port(3000)),
        ("1023", .invalid),
        ("65536", .invalid),
        ("0", .invalid),
        ("-1", .invalid),
        ("+3000", .invalid),
        ("80", .invalid),
        ("abc", .invalid),
        ("30 00", .invalid),
        ("3000a", .invalid),
        ("3.5", .invalid),
        ("٣٠٠٠", .invalid),
        ("99999999999999999999999999", .invalid),
    ])
    func `parse reads the Port field as empty, a port from 1024 to 65535, or invalid`(text: String, expected: MockPort) {
        #expect(MockPort.parse(text) == expected)
    }
}

import Foundation
@testable import Raccoon
import Testing

/// The version written in an exported Environment: the bundle's short version, "dev" without one.
@MainActor
struct AppVersionTests {
    final class VersionedBundle: Bundle, @unchecked Sendable {
        let version: Any?
        init(version: Any?) {
            self.version = version
            super.init()
        }

        override func object(forInfoDictionaryKey key: String) -> Any? {
            key == "CFBundleShortVersionString" ? version : nil
        }
    }

    @Test func `the bundle's short version, or dev when it has none or not a string`() {
        #expect(CompositionRoot.appVersion(bundle: VersionedBundle(version: "1.4.0")) == "1.4.0")
        #expect(CompositionRoot.appVersion(bundle: VersionedBundle(version: nil)) == "dev")
        #expect(CompositionRoot.appVersion(bundle: VersionedBundle(version: 7)) == "dev")
    }
}

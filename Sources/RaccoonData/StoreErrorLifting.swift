// Every boundary: URLSession, files, Keychain, FSEvents. Implements RaccoonDomain's ports.
import Foundation
import RaccoonDomain

/// Runs a Foundation call and lifts whatever it throws into a StoreError, keeping its description.
func lifting<A>(_ wrap: (String) -> StoreError, _ body: () throws -> A) throws(StoreError) -> A {
    do { return try body() } catch { throw wrap(error.localizedDescription) }
}

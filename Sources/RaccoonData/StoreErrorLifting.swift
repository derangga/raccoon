// Every boundary: URLSession, files, Keychain, FSEvents. Implements RaccoonDomain's ports.
import Foundation
import RaccoonDomain

/// Runs a Foundation call and lifts whatever it throws into a StoreError.
func lifting<A>(_ wrap: (String) -> StoreError, _ body: () throws -> A) throws(StoreError) -> A {
    do { return try body() } catch { throw wrap(reason(error)) }
}

/// The short cause, as banners quote it ("Couldn't write a.json: permission denied."): the
/// POSIX error under a Cocoa one when there is one, else the error's own description.
private func reason(_ error: any Error) -> String {
    let underlying = (error as NSError).userInfo[NSUnderlyingErrorKey] as? NSError
    guard let posix = [error as NSError, underlying].compactMap({ $0 }).first(where: { $0.domain == NSPOSIXErrorDomain }) else {
        return error.localizedDescription
    }
    let text = String(cString: strerror(Int32(posix.code)))
    return text.prefix(1).lowercased() + text.dropFirst()
}

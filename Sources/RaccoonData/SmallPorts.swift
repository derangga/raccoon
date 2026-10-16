import AppKit
import Foundation
import RaccoonDomain

public struct DiskFileReading: FileReading {
    public init() {}

    public func read(_ path: String) throws(StoreError) -> Data {
        try lifting({ .unreadable(path: path, reason: $0) }) { try Data(contentsOf: URL(filePath: path)) }
    }
}

/// The app passes `.general`; tests pass a private name so they never touch the user's clipboard.
public struct SystemClipboardWriter: ClipboardWriter {
    private let name: NSPasteboard.Name

    public init(name: NSPasteboard.Name) {
        self.name = name
    }

    public func setString(_ string: String) {
        let pasteboard = NSPasteboard(name: name)
        pasteboard.clearContents()
        pasteboard.setString(string, forType: .string)
    }
}

public struct ContinuousInstantSource: InstantSource {
    public init() {}

    public var now: ContinuousClock.Instant { ContinuousClock.now }
}

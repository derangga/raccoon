import Foundation
import OSLog
import RaccoonDomain

/// Writes the Session file at most once a second (behavior.md §7). A change after a quiet second is
/// written at once; the ones inside the second become one write when it is over, of the Session
/// as it is then.
final class SessionWriter {
    private let store: any SessionStore
    private let instants: any InstantSource
    private let interval: Duration
    private let snapshot: () -> Session
    private var lastWrite: ContinuousClock.Instant?
    /// The write at the end of the second; at most one.
    private(set) var pending: Task<Void, Never>?

    private static let log = Logger(subsystem: "Raccoon", category: "Session")

    init(store: any SessionStore, instants: any InstantSource, interval: Duration = .seconds(1), snapshot: @escaping () -> Session) {
        self.store = store
        self.instants = instants
        self.interval = interval
        self.snapshot = snapshot
    }

    func schedule() {
        guard pending == nil else { return }
        guard let lastWrite, case let wait = lastWrite + interval - instants.now, wait > .zero else { return write() }
        pending = Task { [weak self] in
            try? await Task.sleep(for: wait)
            guard !Task.isCancelled, let self else { return }
            pending = nil
            write()
        }
    }

    /// Quit's write: no waiting, and the caller decides what an unwritable Session means.
    func writeNow() throws(StoreError) {
        pending?.cancel()
        pending = nil
        lastWrite = instants.now
        try store.write(SessionFile.encode(snapshot()))
    }

    /// A failed write loses nothing yet: the Tabs still hold it, and the next change tries again.
    private func write() {
        do throws(StoreError) {
            try writeNow()
        } catch {
            switch error {
            case .unwritable(let path, let reason), .unreadable(let path, let reason), .undecodable(let path, let reason):
                Self.log.error("Session not written to \(path, privacy: .public): \(reason, privacy: .public)")
            }
        }
    }
}

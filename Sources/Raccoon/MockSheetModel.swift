import Foundation
import Observation
import RaccoonDomain

/// What the Mock Server sheet is in; it picks the status, the buttons and the messages
/// (mock-server.md §The Mock Server sheet).
enum MockSheetState: Equatable {
    case stopped
    case starting
    case running(port: UInt16)
    case failed(MockError)
}

/// What sits under the Port field. One place that changes in place, so the row never grows.
enum MockPortNote: Equatable {
    case hint
    case invalid
    /// A running server whose field was edited: what a Restart would bind.
    case restart(MockPort)
    case inUse(UInt16)
}

enum MockSheetAction: Equatable {
    case cancel, start, stop, restart, done
}

/// One row of the route list as the sheet writes it.
struct MockRouteLine: Equatable {
    let method: String
    let path: String
    let detail: String
    let isServed: Bool

    init(method: String, path: String, detail: String, isServed: Bool) {
        self.method = method
        self.path = path
        self.detail = detail
        self.isServed = isServed
    }

    init(_ row: MockRouteRow) {
        let detail = switch row.exampleCount {
        case 0: "Add an Example to serve it."
        case 1: "1 Example"
        default: "\(row.exampleCount) Examples"
        }
        self.init(method: row.method, path: row.path, detail: detail, isServed: row.exampleCount > 0)
    }
}

/// Everything the Mock Server sheet decides: its state, every string, which buttons show and which
/// is the default. The view draws it. Running is the window's (`mockServers`), so a Stop from the
/// menu or a Workspace switch while the sheet is open shows here with nothing to forward.
@Observable
final class MockSheetModel {
    /// What a start or restart did, while the window holds no server.
    private enum Attempt: Equatable {
        case idle
        case starting
        case failed(MockError)
    }

    private let window: WindowModel
    private let collection: String
    private let clipboard: any ClipboardWriter

    private(set) var portText: String
    private var attempt: Attempt
    /// Copy URL was just pressed: the button reads "Copied" for a moment.
    private(set) var copied = false
    @ObservationIgnored private var copiedReset: Task<Void, Never>?

    /// `failure` is a start that just failed, shown as if the sheet had started it.
    init(window: WindowModel, collection: String, failure: MockError?, clipboard: any ClipboardWriter) {
        self.window = window
        self.collection = collection
        self.clipboard = clipboard
        portText = window.mockSettings(collection).port.map(String.init) ?? ""
        attempt = failure.map(Attempt.failed) ?? .idle
    }

    // MARK: State

    var state: MockSheetState {
        if attempt == .starting || window.mockStarting.contains(collection) { return .starting }
        if let server = window.mockServers[collection] { return .running(port: server.port) }
        return switch attempt {
        case .idle, .starting: .stopped
        case .failed(let error): .failed(error)
        }
    }

    /// Renamed, trashed or left behind by a Workspace switch: the sheet has nothing to configure.
    var isCollectionGone: Bool { !window.index.collections.contains { $0.name == collection } }

    private var parsedPort: MockPort { MockPort.parse(portText) }

    var portNote: MockPortNote {
        let parsed = parsedPort
        if parsed == .invalid { return .invalid }
        return switch state {
        case .failed(.portInUse(let port)): .inUse(port)
        case .running(let bound): parsed == .port(bound) ? .hint : .restart(parsed)
        case .stopped, .starting, .failed(.failed): .hint
        }
    }

    // MARK: Strings

    var statusText: String {
        switch state {
        case .stopped, .failed(.portInUse): "Not running"
        case .starting: "Starting…"
        case .running: "Running at \(statusURL ?? "")"
        case .failed(.failed(let reason)): "Couldn't start the Mock Server: \(reason.hasSuffix(".") ? String(reason.dropLast()) : reason)."
        }
    }

    /// The address while running; the view sets it in SF Mono and offers Copy URL beside it.
    var statusURL: String? { window.mockServers[collection]?.url }

    var statusIsError: Bool {
        if case .failed(.failed) = state { true } else { false }
    }

    var portMessage: String {
        switch portNote {
        case .hint: "Use a port from 1024 to 65535, or leave it empty and Raccoon picks one."
        case .invalid: "Use a port from 1024 to 65535."
        case .restart(.port(let port)): "Restart to use port \(port)."
        case .restart: "Restart to use any free port."
        case .inUse(let port): "Port \(port) is in use. Choose another port, or"
        }
    }

    var portMessageIsError: Bool {
        switch portNote {
        case .invalid, .inUse: true
        case .hint, .restart: false
        }
    }

    /// The "use any free port" link at the end of the taken-port sentence.
    var showsUseAnyFreePort: Bool {
        if case .inUse = portNote { true } else { false }
    }

    // MARK: Buttons

    /// Leading to trailing. The default is the last one filled; see `defaultAction`.
    var actions: [MockSheetAction] {
        switch state {
        case .stopped, .starting, .failed: [.cancel, .start]
        case .running: canRestart ? [.stop, .restart, .done] : [.stop, .done]
        }
    }

    /// Return runs it. While running it is never Stop, so Return cannot stop the server.
    var defaultAction: MockSheetAction {
        switch state {
        case .stopped, .starting, .failed: .start
        case .running: canRestart ? .restart : .done
        }
    }

    func isEnabled(_ action: MockSheetAction) -> Bool {
        switch action {
        case .cancel: state != .starting
        case .start: canStart
        case .restart: canRestart
        case .stop, .done: true
        }
    }

    private var canStart: Bool {
        switch state {
        case .stopped, .failed: parsedPort != .invalid
        case .starting, .running: false
        }
    }

    private var canRestart: Bool {
        guard case .running(let bound) = state else { return false }
        let parsed = parsedPort
        return parsed != .invalid && parsed != .port(bound)
    }

    // MARK: Settings

    var allowsCORS: Bool { window.mockServers[collection]?.allowsCORS ?? window.mockSettings(collection).allowsCORS }

    func setAllowsCORS(_ on: Bool) {
        window.setMockAllowsCORS(collection, on)
    }

    /// Every keystroke. A port that parses is remembered (a running server keeps its own until
    /// Restart) and clears a taken-port message, which was about the port before.
    func editPort(_ text: String) {
        portText = text
        let parsed = MockPort.parse(text)
        guard parsed != .invalid else { return }
        window.setMockPort(collection, parsed)
        if case .failed(.portInUse) = attempt { attempt = .idle }
    }

    // MARK: Routes

    private var rows: [MockRouteRow] { window.mockRouteRows(collection) }

    var routeLines: [MockRouteLine] { rows.map(MockRouteLine.init) }

    var routesHeading: String {
        let all = rows
        let served = all.filter { $0.exampleCount > 0 }.count
        return "Serving \(served) of \(all.count) Request\(all.count == 1 ? "" : "s")"
    }

    var routesEmptyText: String? {
        rows.isEmpty ? "Nothing to serve yet. Save a Response as an Example to start." : nil
    }

    // MARK: Actions

    func start() async {
        guard canStart else { return }
        await run { () async throws(MockError) in try await window.startMock(collection) }
    }

    /// The taken-port link: binds a free port; the field then shows the one it got.
    func useAnyFreePort() async {
        guard case .failed(.portInUse) = state else { return }
        await run { () async throws(MockError) in try await window.startMock(collection, onAnotherPort: true) }
    }

    func restart() async {
        guard canRestart else { return }
        await run { () async throws(MockError) in try await window.restartMock(collection) }
    }

    func stop() {
        window.stopMock(collection)
        attempt = .idle
    }

    func copyURL() {
        guard let url = statusURL else { return }
        clipboard.setString(url)
        copied = true
        copiedReset?.cancel()
        copiedReset = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(1500))
            if !Task.isCancelled { self?.copied = false }
        }
    }

    /// Ends the Copied timer when the sheet closes.
    func close() {
        copiedReset?.cancel()
    }

    private func run(_ operation: () async throws(MockError) -> Void) async {
        attempt = .starting
        do throws(MockError) {
            try await operation()
            attempt = .idle
            if let server = window.mockServers[collection] { portText = String(server.port) }
        } catch {
            attempt = .failed(error)
        }
    }
}

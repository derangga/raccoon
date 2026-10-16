import Foundation
import Observation
import RaccoonDomain

/// One Tab's editing state and the ports its send needs. Saving goes through the window, which
/// owns the index and the WriteLedger, so a Tab can never write a file the index does not know.
@Observable
final class TabModel {
    var tab: Tab
    private let transport: any HTTPTransport
    private let secrets: any SecretStore
    private let instants: any InstantSource

    init(transport: any HTTPTransport, secrets: any SecretStore, instants: any InstantSource) {
        tab = Tab(id: TabID(UUID()), source: .draft, definition: .empty, baseline: nil)
        self.transport = transport
        self.secrets = secrets
        self.instants = instants
    }

    /// The line under the URL bar; not part of the Tab, so it is never saved.
    var message: MessageLine?

    /// The multipart file a send could not read; its chip is marked until the next send.
    private(set) var missingFile: String?

    /// After an `invalidURL` send, the URL field is outlined in `error` until the next edit.
    private(set) var isURLInvalid = false

    /// The untrusted-certificate fix: turns the Request Setting on and sends nothing. The user
    /// sends again; Raccoon never does it by itself.
    func allowInsecureTLS() {
        tab.definition.settings.allowsInsecureTLS = true
    }

    /// What the URL bar shows: `url` plus the enabled params (editing.md).
    var urlText: String { URLText.join(tab.definition.url, params: tab.definition.params) }

    /// The typed text is split back into `url` and Params; Disabled Rows keep their place.
    func typeInURLBar(_ text: String) {
        let (base, pairs) = URLText.split(text)
        tab.definition.url = base
        tab.definition.params = Params.merge(pairs, into: tab.definition.params)
        message = message?.afterURLEdit
        isURLInvalid = false
    }

    /// Methods are free text, stored uppercased; a blank one changes nothing.
    func setMethod(_ text: String) {
        let method = text.trimmingCharacters(in: .whitespaces).uppercased()
        guard !method.isEmpty else { return }
        tab.definition.method = method
    }

    /// The body converts (editing.md §Body Type) and the visible Content-Type row follows it.
    func pickBodyType(_ type: BodyType) {
        let old = tab.definition.body.type
        tab.definition.headers = Headers.contentType(tab.definition.headers, from: old, to: type)
        tab.definition.body = BodyConversion.convert(tab.definition.body, to: type)
    }

    var now: ContinuousClock.Instant { instants.now }

    /// Read again once 150 ms have passed; Observation does not see time move.
    var showsSpinner: Bool { tab.response.showsSpinner(at: instants.now) }

    /// The in-flight send (§8). The Tab is the only thing holding it.
    private(set) var inFlight: Task<Void, Never>?

    /// The received body as the viewer draws it: computed once per Response, off the main
    /// actor, and kept here so switching Tabs never recomputes it (cardinality.md). Until it
    /// lands the viewer shows Raw.
    private(set) var presented: Presented?
    private(set) var presenting: Task<Void, Never>?
    /// Counts sends, so a view can tell its text is already this Response's.
    private(set) var sends = 0

    struct Presented: Equatable, Sendable {
        var body: ResponseBody
        var ranges: [HighlightRange]
    }

    @concurrent
    nonisolated static func present(_ response: Response) async -> Presented {
        let body = ResponseBody.presentation(response)
        guard case .pretty(let text, let kind) = body else { return Presented(body: body, ranges: []) }
        return Presented(body: body, ranges: Highlighter.ranges(text, kind: kind))
    }

    /// Resolution runs first, so a request that cannot be sent never shows `.sending`.
    /// One send at a time (§7): a second ⌘↩ while sending does nothing.
    func send() {
        guard inFlight == nil else { return }
        message = message?.afterSendOrPaste
        missingFile = nil
        let resolved: ResolvedRequest
        do throws(ResolveError) {
            resolved = try VariableResolver.resolve(tab.definition)
        } catch {
            tab.response = .notSent(error)
            if case .invalidURL = error { isURLInvalid = true }
            return
        }
        let since = instants.now
        tab.response = .sending(since: since)
        presenting?.cancel()
        presented = nil
        sends += 1
        let send = sends
        inFlight = Task {
            let result: Result<Response, SendError>
            do throws(SendError) {
                result = .success(try await transport.send(resolved))
            } catch {
                result = .failure(error)
            }
            // Cancel has already returned the Tab to .idle, and a newer send may own it now.
            guard !Task.isCancelled else { return }
            inFlight = nil
            switch result {
            case .success(let response):
                tab.response = .received(response)
                presenting = Task {
                    let presented = await Self.present(response)
                    // A newer send owns the viewer now.
                    if send == sends { self.presented = presented }
                }
            case .failure(let error):
                tab.response = .failed(error, after: instants.now - since)
                if case .fileMissing(let path) = error {
                    missingFile = path
                    message = .error("Not sent. \((path as NSString).abbreviatingWithTildeInPath) is missing.")
                }
            }
        }
    }

    /// Cancelling the Task is the whole release: URLSession closes the connection at once
    /// (environment-facts.md, "Cancelling a send"). Not a failure, so the Tab is `.idle`.
    func cancel() {
        guard let inFlight else { return }
        inFlight.cancel()
        self.inFlight = nil
        tab.response = .idle
    }
}

/// The window's Tabs and the ports that touch the Data Folder, the Session and the Keychain.
@Observable
final class WindowModel {
    private(set) var tabs: [TabModel]
    private let dataFolder: any DataFolderStore
    private let folderWatch: any FolderWatch
    private let sessionStore: any SessionStore
    private let secrets: any SecretStore
    private let newTab: () -> TabModel

    /// `newTab` builds a TabModel with its own ports; the window never hands a Tab its stores.
    init(
        dataFolder: any DataFolderStore, folderWatch: any FolderWatch, sessionStore: any SessionStore,
        secrets: any SecretStore, newTab: @escaping () -> TabModel
    ) {
        self.dataFolder = dataFolder
        self.folderWatch = folderWatch
        self.sessionStore = sessionStore
        self.secrets = secrets
        self.newTab = newTab
        tabs = [newTab()]
    }
}

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
    private let files: any FileReading
    private let instants: any InstantSource
    private let clipboard: any ClipboardWriter

    init(transport: any HTTPTransport, secrets: any SecretStore, files: any FileReading, instants: any InstantSource,
         clipboard: any ClipboardWriter) {
        tab = Tab(id: TabID(UUID()), source: .draft, definition: .empty, baseline: nil)
        self.transport = transport
        self.secrets = secrets
        self.files = files
        self.instants = instants
        self.clipboard = clipboard
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

    /// Curl Import (curl.md): a pasted curl command becomes this Tab's request. False means an
    /// ordinary paste. An error is a message and the Tab is unchanged; either way the text is
    /// not inserted. Every Tab is the paste target until Tabs can be opened.
    func pasteInURLBar(_ text: String) -> Bool {
        guard CurlDetector.isCurl(text) else { return false }
        var imported: CurlImport
        do throws(CurlImportError) {
            imported = try CurlImporter.import(text)
        } catch {
            let line = switch error {
            case .noURL: "No URL in this curl command."
            case .unterminatedQuote(let position): "Unterminated quote in this curl command, at character \(position)."
            }
            message = .error(line)
            return true
        }
        var notes: [String] = []
        if !imported.ignoredFlags.isEmpty { notes.append("Ignored: " + imported.ignoredFlags.joined(separator: ", ")) }
        if imported.skippedCommands > 0 { notes.append("\(imported.skippedCommands) more command\(imported.skippedCommands == 1 ? "" : "s")") }
        if !imported.fileReferences.isEmpty {
            // Every @file in a data flag is read as UTF-8 text; one that is not leaves no body.
            var texts: [String] = []
            for path in imported.fileReferences {
                let shown = (path as NSString).abbreviatingWithTildeInPath
                guard let data = try? files.read(path) else {
                    notes.append("\(shown) was not read")
                    texts = []
                    break
                }
                guard let text = String(data: data, encoding: .utf8) else {
                    notes.append("\(shown) is not text, and binary bodies are not supported")
                    texts = []
                    break
                }
                texts.append(text)
            }
            if case .raw(let kind, _) = imported.definition.body, !texts.isEmpty {
                imported.definition.body = .raw(kind, texts.joined(separator: "&"))
            } else {
                imported.definition.body = .none
            }
        }
        // URLSession fails a GET with a body and sends nothing (environment-facts.md Q6).
        if imported.definition.method == "GET" && imported.definition.body != .none {
            notes.append("A GET with a body won't send: macOS refuses it. Change the method or remove the body.")
        }
        tab.definition = imported.definition
        isURLInvalid = false
        message = notes.isEmpty ? nil : .note(notes.joined(separator: ". "))
        return true
    }

    /// Copy as Curl (curl.md): nil while the definition does not resolve, which disables the menu
    /// item. ponytail: the reason is dropped; naming undefined Variables comes with Variables.
    var curlCommand: String? { (try? VariableResolver.resolve(tab.definition)).map(CurlRenderer.render) }

    func copyAsCurl() {
        if let curlCommand { clipboard.setString(curlCommand) }
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
        /// The lines of the text `body` shows, and of the bytes as text, which Raw shows when
        /// the body is Pretty.
        var lines: LineIndex
        var rawLines: LineIndex
        /// Pretty only: Raw is never folded.
        var regions: [FoldRegion]
    }

    @concurrent
    nonisolated static func present(_ response: Response) async -> Presented {
        let body = ResponseBody.presentation(response)
        let rawLines = LineIndex(String(decoding: response.body, as: UTF8.self))
        guard case .pretty(let text, let kind) = body else {
            return Presented(body: body, ranges: [], lines: rawLines, rawLines: rawLines, regions: [])
        }
        let lines = LineIndex(text)
        return Presented(body: body, ranges: Highlighter.ranges(text, kind: kind), lines: lines, rawLines: rawLines,
                         regions: FoldRegion.find(text, lines: lines))
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

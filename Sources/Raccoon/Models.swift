import Foundation
import Observation
import OSLog
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

    /// A Tab banner the user dismisses; never written to the Session.
    var notice: TabNotice?

    /// Where the one editor was when this Tab was last shown, so switching back restores it.
    var viewState = ViewState()

    struct ViewState {
        var section = EditorSection.params
        var body = TextPlace()
        var response = TextPlace()
    }

    struct TextPlace {
        var origin = NSPoint.zero
        var selection = NSRange(location: 0, length: 0)
    }

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

    /// The Tab is going away: its send and its presentation stop now (§8).
    func close() {
        cancel()
        presenting?.cancel()
    }
}

/// A Tab banner that stays until dismissed (design-system §6 Banners). Changed on Disk is not
/// one: it comes from `Tab.isChangedOnDisk` and ends by Reload or Keep Mine.
enum TabNotice: Equatable {
    case notSaved(file: String, reason: String)
    case deletedOnDisk(file: String)
}

/// Where the Data Folder is, how to open a store at a root, and how to remember a new root.
/// The composition root backs it with UserDefaults; tests with a temp dir.
struct DataFolderLocation {
    var root: String
    let open: (String) -> any DataFolderStore
    let remember: (String) -> Void
}

/// The window's Tabs and the ports that touch the Data Folder, the Session and the Keychain.
@Observable
final class WindowModel {
    /// The tab strip's order.
    private(set) var tabs: [TabModel]
    private(set) var selected: TabID?
    private var location: DataFolderLocation
    private let folderWatch: any FolderWatch
    private let sessionStore: any SessionStore
    private let secrets: any SecretStore
    private let makeTab: () -> TabModel
    private let instants: any InstantSource

    /// Where the Data Folder is, shown under the sidebar's empty text.
    var dataFolderRoot: String { location.root }

    /// The sidebar tree; empty while the Data Folder is unavailable.
    private(set) var index = DataFolderIndex([])
    /// Why the Data Folder is unavailable, for the window banner. Drafts and sending still work.
    private(set) var dataFolderError: StoreError?
    /// Raccoon's own writes, so FolderWatch can drop them (behavior.md §7).
    private(set) var ledger = WriteLedger()
    /// The store at the current root; nil while unavailable.
    private var store: (any DataFolderStore)?
    /// The withDataFolder scope (§8): iterating the FolderWatch stream. Cancelling it ends the stream.
    @ObservationIgnored private var watching: Task<Void, Never>?
    @ObservationIgnored private lazy var writer = SessionWriter(store: sessionStore, instants: instants) { [unowned self] in session }

    /// `makeTab` builds a TabModel with its own ports; the window never hands a Tab its stores.
    init(
        dataFolder: DataFolderLocation, folderWatch: any FolderWatch, sessionStore: any SessionStore,
        secrets: any SecretStore, instants: any InstantSource, makeTab: @escaping () -> TabModel
    ) {
        self.location = dataFolder
        self.folderWatch = folderWatch
        self.sessionStore = sessionStore
        self.secrets = secrets
        self.instants = instants
        self.makeTab = makeTab
        tabs = [makeTab()]
        selected = tabs[0].tab.id
        writeOnChange()
    }

    /// ponytail: none until Variables picks one.
    var session: Session {
        Session(tabs: tabs.map(\.tab.snapshot), selected: selected, activeEnvironment: nil)
    }

    /// Every change to a Tab, the order or the selection schedules a write. A Response
    /// changing schedules one too, and writes the same bytes.
    private func writeOnChange() {
        withObservationTracking { _ = session } onChange: { [weak self] in
            Task { @MainActor in
                self?.writer.schedule()
                self?.writeOnChange()
            }
        }
    }

    var selectedTab: TabModel? { tabs.first { $0.tab.id == selected } }

    private static let log = Logger(subsystem: "Raccoon", category: "Session")

    /// Launch: the Tabs as the Session left them, in place of the fresh Draft `init` made.
    /// Every failure keeps that Draft and is logged only (Open UI Q7).
    func relaunch() {
        let session: Session
        do throws(StoreError) {
            guard let data = try sessionStore.read() else { return }
            session = try SessionFile.decode(data)
        } catch {
            switch error {
            case .undecodable(let path, let reason):
                Self.log.error("Session at \(path, privacy: .public) is undecodable: \(reason, privacy: .public)")
                setAsideSession()
            case .unreadable(let path, let reason), .unwritable(let path, let reason):
                Self.log.error("Session at \(path, privacy: .public) not read: \(reason, privacy: .public)")
            }
            return
        }
        // ponytail: a .request Tab comes back as stored; checking it against the Data Folder
        // (found, changed on disk, gone) is the Collections epic's, and goes here.
        let restored = session.tabs.map { snapshot in
            let model = makeTab()
            model.tab = Tab(id: snapshot.id, source: snapshot.source, definition: snapshot.definition, baseline: snapshot.baseline)
            return model
        }
        guard let first = restored.first else { return }
        tabs = restored
        assertOneTabPerRequest()
        selected = restored.contains { $0.tab.id == session.selected } ? session.selected : first.tab.id
    }

    /// ⌘Q, logout, restart. Never asks: the Session keeps Dirty Tabs and Drafts. The snapshot
    /// is written before any Tab is released (§8), and an unwritable Session does not stop quit.
    func quit() {
        do throws(StoreError) {
            try writer.writeNow()
        } catch {
            switch error {
            case .unwritable(let path, let reason), .unreadable(let path, let reason), .undecodable(let path, let reason):
                Self.log.error("Session not written on quit to \(path, privacy: .public): \(reason, privacy: .public)")
            }
        }
        tabs.forEach { $0.close() }
    }

    private func setAsideSession() {
        do throws(StoreError) {
            let path = try sessionStore.setAside()
            Self.log.notice("Session set aside as \(path, privacy: .public)")
        } catch {
            switch error {
            case .unwritable(let path, let reason), .unreadable(let path, let reason), .undecodable(let path, let reason):
                Self.log.error("Session not set aside to \(path, privacy: .public): \(reason, privacy: .public)")
            }
        }
    }

    /// Launch, before relaunch(): Request Tabs are looked up in the index. Synchronous, as the
    /// scan is small; a failure is the banner and an empty sidebar, never a stop.
    func loadDataFolder() {
        let root = location.root
        let store = location.open(root)
        do throws(StoreError) {
            try store.ensureExists()
            index = DataFolderIndex(TreeDecoder.collections(try store.scan()))
        } catch {
            index = DataFolderIndex([])
            dataFolderError = error
            return
        }
        self.store = store
        dataFolderError = nil
        let events = folderWatch.events(root: root)
        watching = Task { [weak self] in
            for await paths in events { self?.filesChanged(paths) }
        }
    }

    /// Choose Folder…: the old scope ends before the new one opens (§8), and a root is
    /// remembered only once it loaded.
    func chooseDataFolder(_ root: String) async {
        watching?.cancel()
        await watching?.value
        watching = nil
        store = nil
        location.root = root
        loadDataFolder()
        if dataFolderError == nil { location.remember(root) }
    }

    /// FolderWatch reported changes: the tree is rebuilt from a fresh scan.
    private func filesChanged(_ paths: [String]) {
        rescan()
    }

    /// ponytail: the whole folder is rescanned; per-Collection rebuilds when a large folder is slow.
    private func rescan() {
        guard let store else { return }
        do throws(StoreError) {
            index = DataFolderIndex(TreeDecoder.collections(try store.scan()))
        } catch {
            dataFolderError = error
        }
    }

    /// A Request Tab is named after its Request, from the index; a Draft by `Tab.title` (tabs.md).
    func name(of tab: Tab) -> String {
        if case .request(let id) = tab.source, let name = index.name(of: id) { return name }
        return tab.title
    }

    /// A click on a sidebar Request row. One Tab per Request: an open one is selected. A file
    /// that broke since the scan opens nothing; the rescan turns its row unreadable.
    func openRequest(_ id: RequestID) {
        if let open = tabs.first(where: { $0.tab.source == .request(id) }) {
            selected = open.tab.id
            return
        }
        guard let store, let path = index.path(of: id) else { return }
        let request: Request
        do throws(StoreError) {
            let data = try store.read(path)
            do throws(RequestFileError) {
                request = try RequestFile.decode(data)
            } catch {
                return rescan()
            }
        } catch {
            return rescan()
        }
        // Someone gave the file another id since the scan.
        guard request.id == id else { return rescan() }
        let model = makeTab()
        model.tab = Tab(id: model.tab.id, source: .request(id), definition: request.definition, baseline: request.definition)
        insertAfterSelected(model)
        assertOneTabPerRequest()
    }

    /// ⌘S on a Request Tab: through the window, which owns the index and the ledger. A failed
    /// write leaves the Tab Dirty and says so in its banner; nothing claims a save that did not land.
    func save(_ id: TabID) {
        guard let model = tabs.first(where: { $0.tab.id == id }), case .request(let requestID) = model.tab.source,
              let store, let path = index.path(of: requestID), let name = index.name(of: requestID)
        else { return }
        let data = RequestFile.encode(Request(id: requestID, name: name, definition: model.tab.definition))
        do throws(StoreError) {
            try store.write(data, to: path)
        } catch {
            switch error {
            case .unwritable(_, let reason), .unreadable(_, let reason), .undecodable(_, let reason):
                model.notice = .notSaved(file: Self.fileName(path), reason: reason)
            }
            return
        }
        ledger.record(path, data)
        model.tab.baseline = model.tab.definition
        model.tab.isChangedOnDisk = false
        model.notice = nil
    }

    /// The file a Request Tab is saved in, as banners name it; nil for a Draft.
    func fileName(of tab: Tab) -> String? {
        guard case .request(let id) = tab.source, let path = index.path(of: id) else { return nil }
        return Self.fileName(path)
    }

    private static func fileName(_ path: String) -> String {
        String(path.split(separator: "/").last ?? "")
    }

    /// §4 Invariants: two Tabs editing one file would each overwrite the other's save.
    private func assertOneTabPerRequest() {
        let ids = tabs.compactMap { if case .request(let id) = $0.tab.source { id } else { nil } }
        precondition(Set(ids).count == ids.count, "two Tabs for one Request")
    }

    /// ⌘T: an empty Draft after the selected Tab.
    func newTab() {
        insertAfterSelected(makeTab())
    }

    private func insertAfterSelected(_ tab: TabModel) {
        let index = tabs.firstIndex { $0.tab.id == selected }.map { $0 + 1 } ?? tabs.endIndex
        tabs.insert(tab, at: index)
        selected = tab.tab.id
    }

    func select(_ id: TabID) {
        guard tabs.contains(where: { $0.tab.id == id }) else { return }
        selected = id
    }

    /// Removes the Tab after stopping its send. The selection moves to the Tab after it, else
    /// the one before; the last Tab is replaced by an empty Draft (Open UI Q1).
    func close(_ id: TabID) {
        guard let index = tabs.firstIndex(where: { $0.tab.id == id }) else { return }
        tabs[index].close()
        tabs.remove(at: index)
        guard !tabs.isEmpty else { return newTab() }
        if selected == id { selected = tabs[min(index, tabs.count - 1)].tab.id }
    }

    /// ⌘1…⌘8 by position, ⌘9 the last Tab, as in Safari and Finder.
    func select(number: Int) {
        let index = number == 9 ? tabs.count - 1 : number - 1
        guard tabs.indices.contains(index) else { return }
        selected = tabs[index].tab.id
    }

    /// ⌃⇥ and ⌃⇧⇥, wrapping at either end.
    func selectNext() { step(1) }
    func selectPrevious() { step(-1) }

    private func step(_ by: Int) {
        guard let index = tabs.firstIndex(where: { $0.tab.id == selected }) else { return }
        selected = tabs[(index + by + tabs.count) % tabs.count].tab.id
    }
}

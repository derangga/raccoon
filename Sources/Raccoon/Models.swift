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

    /// The window's Active Environment and Globals, read at every resolve, so switching the Active
    /// Environment changes what every Tab sends. The window sets it when it makes the Tab.
    @ObservationIgnored var variables: () -> (active: Environment?, globals: Globals) = { (nil, Globals(entries: [])) }

    /// How a Secret Variable resolves: its value, read from the SecretStore now, or its own
    /// `{{name}}`, which the one-pass resolver leaves in the text.
    enum SecretValues { case read, asWritten }

    /// Built for one resolve and dropped with it, never cached, so no secret value is held by a
    /// model (cardinality.md). A secret the store cannot give is absent, so it is undefined (§4).
    func scope(_ secretValues: SecretValues) -> VariableScope {
        let (active, globals) = variables()
        var values: [VariableName: String] = [:]
        // Globals first, so an Environment's secret replaces a Global's, value or absence.
        for (environment, entries) in [(nil, globals.entries), (active?.name, active?.entries ?? [])] {
            for entry in entries where entry.isEnabled && entry.value == .secret {
                values[entry.name] = switch secretValues {
                case .read: try? secrets.get(environment: environment, name: entry.name)
                case .asWritten: "{{\(entry.name.rawValue)}}"
                }
            }
        }
        return VariableScope(active: active, globals: globals, secrets: values)
    }

    /// What the highlights colour by: names only, no Keychain read.
    var kinds: VariableKinds {
        let (active, globals) = variables()
        return VariableKinds(active: active, globals: globals)
    }

    /// Copy as Curl (curl.md): the command, or why there is none, which disables the menu item.
    func curl(includeSecrets: Bool) -> Result<String, ResolveError> {
        do throws(ResolveError) {
            return .success(CurlRenderer.render(try VariableResolver.resolve(tab.definition, scope: scope(includeSecrets ? .read : .asWritten))))
        } catch {
            return .failure(error)
        }
    }

    /// Off by default: a Secret Variable stays `{{name}}` in the copied text.
    func copyAsCurl(includeSecrets: Bool = false) {
        if case .success(let command) = curl(includeSecrets: includeSecrets) { clipboard.setString(command) }
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
            resolved = try VariableResolver.resolve(tab.definition, scope: scope(.read))
        } catch {
            switch error {
            case .undefined(let names):
                // The red underlines are already on screen; the last Response stays (board 04).
                message = .undefined(names, in: variables().active?.name)
            case .invalidURL:
                tab.response = .notSent(error)
                isURLInvalid = true
            }
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

/// Where the Save Request sheet puts a Draft: an existing Collection or Folder, by path, or a
/// Collection it creates (only offered while there are none).
enum SaveLocation: Equatable {
    case folder(String)
    case newCollection(String)
}

/// Where the open Workspace's Data Folder is, every remembered Workspace, how to open a store at
/// a root, and how to remember the open root and the list. The composition root backs it with
/// UserDefaults; tests with a temp dir.
struct DataFolderLocation {
    var root: String
    var workspaces: [String] = []
    let open: (String) -> any DataFolderStore
    let remember: (String) -> Void
    var rememberWorkspaces: ([String]) -> Void = { _ in }
}

/// An environments/*.json that did not decode: listed in the Environments sheet, read-only.
struct BrokenEnvironment: Equatable {
    var name: String
    var reason: String
}

/// Why the Environments sheet could not rename an Environment.
enum EnvironmentEditError: Error, Equatable {
    case empty
    /// Another Environment has this name, ignoring case.
    case nameTaken(String)
    case store(StoreError)
    case secret(SecretError)
}

/// Why the Environments sheet could not mark or unmark a Secret Variable.
enum SecretEditError: Error, Equatable {
    case store(StoreError)
    case secret(SecretError)
}

/// The window's Tabs and the ports that touch the Data Folder, the Session and the Keychain.
@Observable
final class WindowModel {
    /// The tab strip's order.
    private(set) var tabs: [TabModel]
    private(set) var selected: TabID?
    private var location: DataFolderLocation
    private let folderWatch: any FolderWatch
    private let sessionStores: (String) -> any SessionStore
    private let makeSecrets: (WorkspaceID?) -> any SecretStore
    private let makeTab: (any SecretStore) -> TabModel
    private let instants: any InstantSource
    /// The open Workspace's: a new Tab gets these secrets.
    private var sessionStore: any SessionStore
    private var secrets: any SecretStore

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
    /// nil while the open Workspace's Data Folder cannot be read: its Session is neither read
    /// nor written until it can (workspaces.md).
    @ObservationIgnored private var writer: SessionWriter?

    /// Every remembered Workspace, as paths.
    var workspaces: [String] { location.workspaces }

    /// globals.json and environments/*.json from the last scan, so they follow every rescan. A
    /// file that does not decode is in `brokenEnvironments` or `globalsProblem`, not here (§4).
    private(set) var globals = Globals(entries: [])
    private(set) var environments: [Environment] = []
    /// Files that did not decode, kept apart: the Environments sheet lists them read-only with
    /// the reason, and nothing else uses them or writes them (§4).
    private(set) var brokenEnvironments: [BrokenEnvironment] = []
    /// Why globals.json did not decode; nil when it did, or is not there.
    private(set) var globalsProblem: String?
    /// One per window, not per Tab (variables.md): switching changes what every Tab sends. A
    /// name whose file is gone resolves as none.
    private(set) var activeEnvironment: String?

    /// The toolbar pop-up and ⌃E. The Session write follows from `session` changing.
    func pickActiveEnvironment(_ name: String?) {
        activeEnvironment = name
    }

    /// `sessionStore` and `secrets` build the open Workspace's ports from its root and its id (nil
    /// when raccoon.json gave none). `makeTab` builds a TabModel with its own ports and the
    /// Workspace's secrets; the window never hands a Tab its other stores.
    init(
        dataFolder: DataFolderLocation, folderWatch: any FolderWatch, sessionStore: @escaping (String) -> any SessionStore,
        secrets: @escaping (WorkspaceID?) -> any SecretStore, instants: any InstantSource,
        makeTab: @escaping (any SecretStore) -> TabModel
    ) {
        self.location = dataFolder
        self.folderWatch = folderWatch
        self.sessionStores = sessionStore
        self.makeSecrets = secrets
        self.instants = instants
        self.makeTab = makeTab
        let noID = secrets(nil)
        self.sessionStore = sessionStore(dataFolder.root)
        self.secrets = noID
        tabs = [makeTab(noID)]
        selected = tabs[0].tab.id
        writer = makeWriter()
        connect(tabs[0])
        writeOnChange()
    }

    private func makeWriter() -> SessionWriter {
        SessionWriter(store: sessionStore, instants: instants) { [unowned self] in session }
    }

    private func newTabModel() -> TabModel { connect(makeTab(secrets)) }

    /// Every Tab resolves against the window's Variables.
    @discardableResult
    private func connect(_ model: TabModel) -> TabModel {
        model.variables = { [weak self] in self?.variables ?? (nil, Globals(entries: [])) }
        return model
    }

    /// The Active Environment, if its file is still there, and Globals: what every Tab resolves against.
    var variables: (active: Environment?, globals: Globals) {
        (environments.first { $0.name == activeEnvironment }, globals)
    }

    var session: Session {
        Session(tabs: tabs.map(\.tab.snapshot), selected: selected, activeEnvironment: activeEnvironment)
    }

    /// Every change to a Tab, the order or the selection schedules a write. A Response
    /// changing schedules one too, and writes the same bytes.
    private func writeOnChange() {
        withObservationTracking { _ = session } onChange: { [weak self] in
            Task { @MainActor in
                self?.writer?.schedule()
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
        // Its file gone since the last run: none (§4).
        activeEnvironment = environments.contains { $0.name == session.activeEnvironment } ? session.activeEnvironment : nil
        let restored = session.tabs.map { snapshot in
            let model = newTabModel()
            model.tab = restoredTab(snapshot)
            return model
        }
        guard let first = restored.first else { return }
        tabs = restored
        assertOneTabPerRequest()
        selected = restored.contains { $0.tab.id == session.selected } ? session.selected : first.tab.id
    }

    /// A Request Tab checked against its file (tabs.md §relaunch). loadDataFolder ran first, so
    /// the file is in the launch scan. A Request that is gone, or no longer reads, is a Draft.
    private func restoredTab(_ snapshot: TabSnapshot) -> Tab {
        var tab = Tab(id: snapshot.id, source: snapshot.source, definition: snapshot.definition, baseline: snapshot.baseline)
        guard case .request(let id) = snapshot.source else { return tab }
        guard let path = index.path(of: id), let data = lastScan.files[path], let disk = try? RequestFile.decode(data).definition else {
            tab.source = .draft
            tab.baseline = nil
            return tab
        }
        guard disk != snapshot.baseline else { return tab }
        if tab.isDirty {
            tab.isChangedOnDisk = true
        } else {
            tab.definition = disk
        }
        tab.baseline = disk
        return tab
    }

    /// ⌘Q, logout, restart. Never asks: the Session keeps Dirty Tabs and Drafts. The snapshot
    /// is written before any Tab is released (§8), and an unwritable Session does not stop quit.
    func quit() {
        writeSession(when: "on quit")
        tabs.forEach { $0.close() }
    }

    /// Writes the open Workspace's Session at once. An unwritable one is logged: it never stops
    /// quit or a switch.
    private func writeSession(when: String) {
        do throws(StoreError) {
            try writer?.writeNow()
        } catch {
            switch error {
            case .unwritable(let path, let reason), .unreadable(let path, let reason), .undecodable(let path, let reason):
                Self.log.error("Session not written \(when, privacy: .public) to \(path, privacy: .public): \(reason, privacy: .public)")
            }
        }
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

    /// Loads the open root as a Workspace (workspaces.md): raccoon.json gives its id, which builds
    /// its SecretStore, its Session is restored, and FolderWatch starts. A failed scan is the
    /// banner, an empty sidebar and one empty Draft whose Session is neither read nor written. Only
    /// the first launch, with no Workspace listed yet, creates the root. Synchronous, as the scan is
    /// small.
    func loadDataFolder() {
        let root = location.root
        let store = location.open(root)
        let firstLaunch = location.workspaces.isEmpty
        list(root)
        ledger = WriteLedger()
        unreadableFiles = [:]
        activeEnvironment = nil
        var id: WorkspaceID?
        do throws(StoreError) {
            if firstLaunch { try store.ensureExists() }
            scanCount += 1
            lastScan = try store.scan()
            index = DataFolderIndex(TreeDecoder.collections(lastScan))
        } catch {
            index = DataFolderIndex([])
            lastScan = DataFolderScan(files: [:], folders: [])
            dataFolderError = error
            self.store = nil
            writer = nil
            sessionStore = sessionStores(root)
            secrets = makeSecrets(nil)
            resetTabs()
            return
        }
        self.store = store
        dataFolderError = nil
        if let bytes = lastScan.files["raccoon.json"] {
            do throws(StoreError) {
                id = try WorkspaceFile.decode(bytes)
            } catch {
                Self.log.error("raccoon.json in \(root, privacy: .public) is undecodable: \(String(describing: error), privacy: .public)")
            }
        } else {
            let new = WorkspaceID(UUID())
            let bytes = WorkspaceFile.encode(new)
            do throws(StoreError) {
                try store.write(bytes, to: "raccoon.json")
                ledger.record("raccoon.json", bytes)
                lastScan.files["raccoon.json"] = bytes
                id = new
            } catch {
                dataFolderError = error
            }
        }
        secrets = makeSecrets(id)
        sessionStore = sessionStores(root)
        writer = makeWriter()
        resetTabs()
        relaunch()
        let events = folderWatch.events(root: root)
        watching = Task { [weak self] in
            for await paths in events { self?.filesChanged(paths) }
        }
    }

    /// One empty Draft holding the open Workspace's secrets.
    private func resetTabs() {
        tabs = [newTabModel()]
        selected = tabs[0].tab.id
    }

    /// Remembers `root` among the Workspaces; one already listed is unchanged.
    private func list(_ root: String) {
        guard !location.workspaces.contains(where: { Self.standard($0) == Self.standard(root) }) else { return }
        location.workspaces.append(root)
        location.rememberWorkspaces(location.workspaces)
    }

    /// Open Workspace…: a folder already listed is not added twice.
    func openWorkspace(_ root: String) async {
        list(root)
        await switchWorkspace(root)
    }

    /// New Workspace…: creates the folder at `root`, lists it and opens it. Returns the alert's
    /// text when it cannot, and writes nothing: the name is taken, or the folder cannot be made.
    func newWorkspace(_ root: String) async -> String? {
        let url = URL(filePath: root)
        let name = url.lastPathComponent
        guard !FileManager.default.fileExists(atPath: root) else {
            return "A folder named “\(name)” already exists. Use Open Workspace… to add it."
        }
        do throws(StoreError) {
            try location.open(url.deletingLastPathComponent().path).createDirectory(name)
        } catch {
            switch error {
            case .unwritable(_, let reason), .unreadable(_, let reason), .undecodable(_, let reason):
                return "Couldn't create “\(name)”: \(reason)."
            }
        }
        await openWorkspace(root)
        return nil
    }

    /// Remove from List forgets a Workspace; its folder and Keychain items stay, its Session file
    /// goes. The open one switches to the first other by title first. The last one stays.
    func removeWorkspace(_ root: String) async {
        let path = Self.standard(root)
        if path == Self.standard(location.root) {
            guard let other = WorkspaceList.titles(location.workspaces).first(where: { Self.standard($0.path) != path }) else { return }
            await switchWorkspace(other.path)
        }
        location.workspaces.removeAll { Self.standard($0) == path }
        location.rememberWorkspaces(location.workspaces)
        do throws(StoreError) {
            try sessionStores(root).delete()
        } catch {
            switch error {
            case .unwritable(let path, let reason), .unreadable(let path, let reason), .undecodable(let path, let reason):
                Self.log.error("Session not deleted at \(path, privacy: .public): \(reason, privacy: .public)")
            }
        }
    }

    private static func standard(_ path: String) -> String { URL(filePath: path).standardized.path }

    /// The old scope ends before the new one opens (§8): Tabs first, which cancels their sends,
    /// then the FolderWatch stream.
    private func endDataFolderScope() async {
        tabs.forEach { $0.close() }
        watching?.cancel()
        await watching?.value
        watching = nil
        store = nil
    }

    /// A row of the Workspace pop-up, or Open Workspace… on a folder already listed. The open
    /// Workspace's Session is written first, as on quit, and nothing asks about Dirty Tabs or
    /// Drafts: the Session keeps them. The root is remembered even when it failed to load, so a
    /// relaunch shows the same banner.
    func switchWorkspace(_ root: String) async {
        guard Self.standard(root) != Self.standard(location.root) else { return }
        writeSession(when: "on switch")
        await endDataFolderScope()
        location.root = root
        loadDataFolder()
        location.remember(root)
    }

    /// Scans of the Data Folder so far: a watch batch is one, whatever its size.
    private(set) var scanCount = 0
    /// Open Requests whose file is still there but no longer reads; they are never written over.
    private var unreadableFiles: [RequestID: String] = [:]

    /// A FolderWatch batch (collections.md §filesChanged). Our own writes are dropped by the
    /// ledger; anything else rescans once, then each open Request Tab follows its file.
    private func filesChanged(_ paths: [String]) {
        guard let store else { return }
        // A path that reads as nothing (gone, or a folder) is ours if Raccoon removed or made it.
        guard !paths.allSatisfy({ ledger.isOurs($0, try? store.read($0)) }) else { return }
        let before = index
        guard let scan = rescan() else { return }
        followTabs(before: before, scan: scan)
    }

    /// Each open Request Tab after the tree changed: it follows its RequestID to a new path,
    /// reloads or turns Changed on Disk, or becomes a Draft when its file is gone.
    private func followTabs(before: DataFolderIndex, scan: DataFolderScan) {
        for model in tabs {
            guard case .request(let id) = model.tab.source else { continue }
            guard let path = index.path(of: id) else {
                guard let old = before.path(of: id) ?? unreadableFiles[id] else { continue }
                if scan.files[old] != nil {
                    // Still there, but unreadable or a duplicate now: left alone, never written over.
                    unreadableFiles[id] = old
                } else {
                    unreadableFiles[id] = nil
                    model.tab.source = .draft
                    model.tab.baseline = nil
                    model.tab.isChangedOnDisk = false
                    model.notice = .deletedOnDisk(file: Self.fileName(old))
                }
                continue
            }
            unreadableFiles[id] = nil
            // The index decoded this file a moment ago, so it decodes.
            guard let data = scan.files[path], let disk = try? RequestFile.decode(data).definition, disk != model.tab.baseline
            else { continue }
            if model.tab.isDirty {
                model.tab.baseline = disk
                model.tab.isChangedOnDisk = true
            } else {
                model.tab.definition = disk
                model.tab.baseline = disk
            }
        }
    }

    // MARK: New Collection, New Folder, rename, move, Move to Trash

    /// The last scan, kept up to date with Raccoon's own changes so they rebuild the tree with
    /// no disk scan.
    private var lastScan = DataFolderScan(files: [:], folders: []) {
        didSet { loadVariables() }
    }

    private static let variablesLog = Logger(subsystem: "Raccoon", category: "Variables")

    /// Environments are the `.json` files directly in `environments/`, named by their file name,
    /// sorted as Finder sorts.
    private func loadVariables() {
        func read(_ path: String) -> (entries: [VariableEntry], problem: String?)? {
            guard let data = lastScan.files[path] else { return nil }
            do throws(StoreError) {
                let file = try EnvironmentFile.decode(data, path: path)
                if !file.droppedSecretValues.isEmpty {
                    let names = file.droppedSecretValues.map(\.rawValue).joined(separator: ", ")
                    Self.variablesLog.error("\(path, privacy: .public) holds a value for secret \(names, privacy: .public); it was ignored")
                }
                return (file.entries, nil)
            } catch {
                switch error {
                case .undecodable(let path, let reason), .unreadable(let path, let reason), .unwritable(let path, let reason):
                    Self.variablesLog.error("\(path, privacy: .public) not used: \(reason, privacy: .public)")
                    return ([], reason)
                }
            }
        }
        let globalsFile = read(Self.globalsPath)
        globals = Globals(entries: globalsFile?.entries ?? [])
        globalsProblem = globalsFile?.problem
        var good: [Environment] = []
        var broken: [BrokenEnvironment] = []
        for path in lastScan.files.keys where path.hasPrefix(Self.environmentsFolder) && path.hasSuffix(".json") && !path.dropFirst(Self.environmentsFolder.count).contains("/") {
            let name = String(path.dropFirst(Self.environmentsFolder.count).dropLast(".json".count))
            guard let file = read(path) else { continue }
            if let problem = file.problem { broken.append(BrokenEnvironment(name: name, reason: problem)) } else { good.append(Environment(name: name, entries: file.entries)) }
        }
        let byName = { (a: String, b: String) in a.localizedStandardCompare(b) == .orderedAscending }
        environments = good.sorted { byName($0.name, $1.name) }
        brokenEnvironments = broken.sorted { byName($0.name, $1.name) }
    }

    // MARK: The Environments sheet

    private static let globalsPath = "globals.json"
    private static let environmentsFolder = "environments/"

    /// `set` is an Environment's name, nil for Globals (as in SecretStore).
    private static func path(of set: String?) -> String {
        set.map { environmentsFolder + $0 + ".json" } ?? globalsPath
    }

    /// The rows of a set; nil when its file does not decode, so the sheet shows no table for it.
    func entries(of set: String?) -> [VariableEntry]? {
        guard let set else { return globalsProblem == nil ? globals.entries : nil }
        return environments.first { $0.name == set }?.entries
    }

    /// A set's file, whole: edits go through the window, which owns the ledger. One that does
    /// not decode is never written over (§4).
    func write(_ entries: [VariableEntry], to set: String?) throws(StoreError) {
        let path = Self.path(of: set)
        let store = try requireStore()
        if set == nil ? globalsProblem != nil : brokenEnvironments.contains(where: { $0.name == set }) {
            throw .unwritable(path: path, reason: "Raccoon won't change a file it can't read.")
        }
        let bytes = EnvironmentFile.encode(entries)
        try store.write(bytes, to: path)
        var scan = lastScan
        scan.files[path] = bytes
        apply(scan, touched: [path])
    }

    /// Rewrites the file without the row; then, for a secret, deletes its Keychain item, so a
    /// failed write leaves both (variables.md order, reversed as for unmark).
    func removeVariable(at index: Int, from set: String?) throws(StoreError) {
        guard var entries = entries(of: set), entries.indices.contains(index) else { return }
        let removed = entries.remove(at: index)
        try write(entries, to: set)
        guard removed.value == .secret else { return }
        do throws(SecretError) {
            try secrets.delete(environment: set, name: removed.name)
        } catch {
            Self.variablesLog.error("Keychain item of \(removed.name.rawValue, privacy: .public) not deleted: \(String(describing: error), privacy: .public)")
        }
    }

    /// Marks a plain row: its value goes to the Keychain first, then the file is rewritten without
    /// it, so a failure at either step never loses the value (variables.md). An empty value stores
    /// nothing and clears any old item of that name, so none is sent: the row is a secret with no
    /// value yet.
    func markSecret(at index: Int, in set: String?) throws(SecretEditError) {
        guard var entries = entries(of: set), entries.indices.contains(index), case .plain(let value) = entries[index].value else { return }
        let name = entries[index].name
        do throws(SecretError) {
            if value.isEmpty { try secrets.delete(environment: set, name: name) } else { try secrets.set(value, environment: set, name: name) }
        } catch {
            throw .secret(error)
        }
        entries[index].value = .secret
        do throws(StoreError) {
            try write(entries, to: set)
        } catch {
            if !value.isEmpty {
                do throws(SecretError) {
                    try secrets.delete(environment: set, name: name)
                } catch {
                    Self.variablesLog.error("Keychain item of \(name.rawValue, privacy: .public) not removed after a failed save: \(String(describing: error), privacy: .public)")
                }
            }
            throw .store(error)
        }
    }

    /// Unmarks a secret row: the file is rewritten with the value first, then the Keychain item is
    /// deleted. A secret the Keychain cannot give becomes an empty value and nothing is deleted.
    func unmarkSecret(at index: Int, in set: String?) throws(StoreError) {
        guard var entries = entries(of: set), entries.indices.contains(index), entries[index].value == .secret else { return }
        let name = entries[index].name
        let stored = try? secrets.get(environment: set, name: name)
        entries[index].value = .plain(stored ?? "")
        try write(entries, to: set)
        guard stored != nil else { return }
        do throws(SecretError) {
            try secrets.delete(environment: set, name: name)
        } catch {
            Self.variablesLog.error("Keychain item of \(name.rawValue, privacy: .public) not deleted: \(String(describing: error), privacy: .public)")
        }
    }

    /// A plain value typed in the inspector's Variables pane. `index` is where the pane saw the
    /// row; if the file moved under it, the enabled row of that name is written instead.
    func setValue(_ value: String, for name: VariableName, at index: Int, in set: String?) throws(StoreError) {
        var entries = try readableEntries(of: set)
        let row = entries.indices.contains(index) && entries[index].name == name ? index : entries.firstIndex { $0.isEnabled && $0.name == name }
        guard let row, entries[row].value != .plain(value) else { return }
        entries[row].value = .plain(value)
        try write(entries, to: set)
    }

    /// A Not defined name given a value in the inspector: a disabled row of that name is enabled
    /// with it, else a new row goes at the end, so the file never holds the name twice.
    func define(_ name: VariableName, value: String, in set: String?) throws(StoreError) {
        var entries = try readableEntries(of: set)
        if let row = entries.firstIndex(where: { $0.name == name }) {
            entries[row] = VariableEntry(name: name, value: .plain(value))
        } else {
            entries.append(VariableEntry(name: name, value: .plain(value)))
        }
        try write(entries, to: set)
    }

    /// A set's rows to edit; a file that does not decode, or is gone, is refused as `write` refuses.
    private func readableEntries(of set: String?) throws(StoreError) -> [VariableEntry] {
        guard let entries = entries(of: set) else {
            throw .unwritable(path: Self.path(of: set), reason: "Raccoon won't change a file it can't read.")
        }
        return entries
    }

    /// A secret's value typed in the sheet. The file holds no value, so it is not touched.
    func setSecretValue(_ value: String, at index: Int, in set: String?) throws(SecretError) {
        guard let entries = entries(of: set), entries.indices.contains(index), entries[index].value == .secret else { return }
        try secrets.set(value, environment: set, name: entries[index].name)
    }

    /// The secrets of a set the Keychain cannot give (absent or unreadable): one read each, and
    /// only whether it answered is kept.
    func missingSecrets(in set: String?) -> Set<VariableName> {
        Set((entries(of: set) ?? []).filter { $0.value == .secret && (try? secrets.get(environment: set, name: $0.name)) == nil }.map(\.name))
    }

    /// environments/New Environment.json, empty; " 2", " 3"… when taken. Returns its name.
    func newEnvironment() throws(StoreError) -> String {
        let store = try requireStore()
        let name = RequestFileName.unique("New Environment", taken: Set(environments.map(\.name) + brokenEnvironments.map(\.name)))
        let path = Self.path(of: name)
        let folder = String(Self.environmentsFolder.dropLast())
        let bytes = EnvironmentFile.encode([])
        try store.createDirectory(folder)
        try store.write(bytes, to: path)
        var scan = lastScan
        let madeFolder = scan.folders.insert(folder).inserted
        scan.files[path] = bytes
        apply(scan, touched: madeFolder ? [folder, path] : [path])
        return name
    }

    /// Its secrets are copied to the new name first, then the file moves, then the old Keychain
    /// items go: a failure at any step leaves the old name whole. The Active Environment follows.
    /// Returns the name it has now: the proposed one as a file name.
    @discardableResult
    func renameEnvironment(_ old: String, to proposed: String) throws(EnvironmentEditError) -> String {
        let new = RequestFileName.sanitised(proposed.trimmingCharacters(in: .whitespaces))
        guard !new.isEmpty else { throw .empty }
        guard new != old else { return old }
        if let clash = EnvironmentName.clash(new, among: environments.map(\.name) + brokenEnvironments.map(\.name), except: old) {
            throw .nameTaken(clash)
        }
        guard let environment = environments.first(where: { $0.name == old }) else {
            throw .store(.unreadable(path: Self.path(of: old), reason: "The file is gone."))
        }
        let names = environment.entries.filter { $0.value == .secret }.map(\.name)
        var copied: [VariableName] = []
        let undo = { [secrets] in for name in copied { try? secrets.delete(environment: new, name: name) } }
        do throws(SecretError) {
            for name in names {
                guard let value = try secrets.get(environment: old, name: name) else { continue }
                try secrets.set(value, environment: new, name: name)
                copied.append(name)
            }
        } catch {
            undo()
            throw .secret(error)
        }
        do throws(StoreError) {
            try requireStore().move(Self.path(of: old), to: Self.path(of: new))
        } catch {
            undo()
            throw .store(error)
        }
        if activeEnvironment == old { activeEnvironment = new }
        apply(lastScan.moving(Self.path(of: old), to: Self.path(of: new)), touched: [Self.path(of: old), Self.path(of: new)])
        for name in names {
            do throws(SecretError) {
                try secrets.delete(environment: old, name: name)
            } catch {
                Self.variablesLog.error("Keychain item of \(name.rawValue, privacy: .public) in \(old, privacy: .public) not deleted: \(String(describing: error), privacy: .public)")
            }
        }
        return new
    }

    /// To the Trash; its Keychain items stay, and No Environment is active if it was.
    func deleteEnvironment(_ name: String) throws(StoreError) {
        try trash(Self.path(of: name))
    }

    /// Raccoon changed the disk itself: every touched path goes in the ledger, so the watch
    /// echo is dropped, and the tree is rebuilt from the edited scan.
    private func apply(_ scan: DataFolderScan, touched: Set<String>) {
        for path in touched { ledger.record(path, scan.files[path]) }
        lastScan = scan
        let before = index
        index = DataFolderIndex(TreeDecoder.collections(scan))
        followTabs(before: before, scan: scan)
    }

    private func requireStore() throws(StoreError) -> any DataFolderStore {
        guard let store else { throw .unwritable(path: location.root, reason: "the Data Folder is unavailable") }
        return store
    }

    private func folderNames(in parent: String) -> Set<String> {
        Set(lastScan.folders.filter { Self.parent(of: $0) == parent }.map(Self.fileName))
    }

    private static func parent(of path: String) -> String {
        path.range(of: "/", options: .backwards).map { String(path[..<$0.lowerBound]) } ?? ""
    }

    private static func joined(_ parent: String, _ name: String) -> String {
        parent.isEmpty ? name : parent + "/" + name
    }

    func newCollection(_ name: String) throws(StoreError) {
        try newFolder(name, in: "")
    }

    /// `parent` "" makes a Collection.
    func newFolder(_ name: String, in parent: String) throws(StoreError) {
        let path = Self.joined(parent, RequestFileName.unique(RequestFileName.sanitised(name), taken: folderNames(in: parent)))
        try requireStore().createDirectory(path)
        var scan = lastScan
        scan.folders.insert(path)
        apply(scan, touched: [path])
    }

    /// A Collection or Folder gets a new folder name; a Request a new name inside its file,
    /// and the file name to match.
    func rename(_ path: String, to name: String) throws(StoreError) {
        let store = try requireStore()
        let parent = Self.parent(of: path)
        guard let data = lastScan.files[path] else {
            let newPath = Self.joined(parent, RequestFileName.unique(RequestFileName.sanitised(name), taken: folderNames(in: parent).subtracting([Self.fileName(path)])))
            guard newPath != path else { return }
            try store.move(path, to: newPath)
            apply(lastScan.moving(path, to: newPath), touched: lastScan.paths(under: path).union(lastScan.moving(path, to: newPath).paths(under: newPath)))
            return
        }
        // Unreadable rows offer no Rename: only a Request has a name inside.
        guard var request = try? RequestFile.decode(data) else { return }
        request.name = name
        let bytes = RequestFile.encode(request)
        let newPath = Self.joined(parent, RequestFileName.make(name, taken: index.fileNames(in: parent).subtracting([Self.fileName(path)])))
        if newPath != path { try store.move(path, to: newPath) }
        try store.write(bytes, to: newPath)
        var scan = lastScan.moving(path, to: newPath)
        scan.files[newPath] = bytes
        apply(scan, touched: [path, newPath])
    }

    /// Into a Collection or Folder, keeping its name (" 2" if taken there).
    func move(_ path: String, to folder: String) throws(StoreError) {
        let name = Self.fileName(path)
        let isFile = lastScan.files[path] != nil
        let taken = isFile ? index.fileNames(in: folder) : folderNames(in: folder)
        let newName = isFile
            ? RequestFileName.unique(String(name.dropLast(".json".count)), extension: ".json", taken: taken)
            : RequestFileName.unique(name, taken: taken)
        let newPath = Self.joined(folder, newName)
        guard newPath != path, !(folder + "/").hasPrefix(path + "/") else { return }
        try requireStore().move(path, to: newPath)
        let moved = lastScan.moving(path, to: newPath)
        apply(moved, touched: lastScan.paths(under: path).union(moved.paths(under: newPath)))
    }

    /// To the Trash, never unlinked. Open Tabs on what went become Drafts.
    func trash(_ path: String) throws(StoreError) {
        try requireStore().trash(path)
        apply(lastScan.removing(path), touched: lastScan.paths(under: path))
        if let active = activeEnvironment, Self.path(of: active) == path { activeEnvironment = nil }
    }

    /// Reload on the Changed on Disk banner: the file wins.
    func reload(_ id: TabID) {
        guard let model = tabs.first(where: { $0.tab.id == id }), let baseline = model.tab.baseline else { return }
        model.tab.definition = baseline
        model.tab.isChangedOnDisk = false
    }

    /// Keep Mine: the edits stay, Dirty against the new file, so the next ⌘S writes over it.
    func keepMine(_ id: TabID) {
        tabs.first { $0.tab.id == id }?.tab.isChangedOnDisk = false
    }

    /// The tree from a fresh scan. ponytail: the whole folder each time; per-Collection rebuilds
    /// when a large folder makes this slow.
    @discardableResult
    private func rescan() -> DataFolderScan? {
        guard let store else { return nil }
        scanCount += 1
        do throws(StoreError) {
            let scan = try store.scan()
            lastScan = scan
            index = DataFolderIndex(TreeDecoder.collections(scan))
            return scan
        } catch {
            dataFolderError = error
            return nil
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
                rescan(); return
            }
        } catch {
            rescan(); return
        }
        // Someone gave the file another id since the scan.
        guard request.id == id else { rescan(); return }
        let model = newTabModel()
        model.tab = Tab(id: model.tab.id, source: .request(id), definition: request.definition, baseline: request.definition)
        insertAfterSelected(model)
        assertOneTabPerRequest()
    }

    /// ⌘S on a Request Tab: through the window, which owns the index and the ledger. A failed
    /// write leaves the Tab Dirty and says so in its banner; nothing claims a save that did not land.
    func save(_ id: TabID) {
        guard let model = tabs.first(where: { $0.tab.id == id }), case .request(let requestID) = model.tab.source else { return }
        if let broken = unreadableFiles[requestID] {
            model.notice = .notSaved(file: Self.fileName(broken), reason: "it can't be read, and Raccoon won't change it")
            return
        }
        guard let store, let path = index.path(of: requestID), let name = index.name(of: requestID) else { return }
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
        lastScan.files[path] = data
        model.tab.baseline = model.tab.definition
        model.tab.isChangedOnDisk = false
        model.notice = nil
    }

    /// The sheet's default Location: where the last Draft was saved. Not kept across relaunch.
    private(set) var lastSaveLocation: String?

    /// Save on a Draft, once the sheet answered: a new RequestID and file, and the Tab becomes
    /// that Request. A failed write leaves it a Draft, with Not saved in its banner.
    func saveDraft(_ id: TabID, name: String, in location: SaveLocation) {
        guard let model = tabs.first(where: { $0.tab.id == id }), model.tab.source == .draft, let store else { return }
        let folder = switch location {
        case .folder(let path): path
        case .newCollection(let name): RequestFileName.sanitised(name)
        }
        let file = RequestFileName.make(name, taken: index.fileNames(in: folder))
        let path = folder + "/" + file
        let requestID = RequestID(UUID())
        let data = RequestFile.encode(Request(id: requestID, name: name, definition: model.tab.definition))
        do throws(StoreError) {
            if case .newCollection = location { try store.createDirectory(folder) }
            try store.write(data, to: path)
        } catch {
            switch error {
            case .unwritable(_, let reason), .unreadable(_, let reason), .undecodable(_, let reason):
                model.notice = .notSaved(file: file, reason: reason)
            }
            return
        }
        ledger.record(path, data)
        lastScan.files[path] = data
        if case .newCollection = location { lastScan.folders.insert(folder); ledger.record(folder, nil) }
        // insert needs the Collection in the tree already; a new one comes from the rescan.
        if case .newCollection = location { rescan() } else { index.insert(requestID, name: name, method: model.tab.definition.method, path: path) }
        model.tab.source = .request(requestID)
        model.tab.baseline = model.tab.definition
        model.notice = nil
        lastSaveLocation = folder
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
        insertAfterSelected(newTabModel())
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

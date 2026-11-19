import AppKit
@testable import Raccoon
import RaccoonData
import RaccoonDomain
import RaccoonTesting
import Testing

/// An Example in a Tab of its own: opening, ⌘S, Changed on Disk and the Session, over a live store in a temp dir.
@MainActor
struct OpenExampleTests {
    let base = SaveRequestTests()
    let request = OpenRequestTests.charge.id
    let path = "Payments API/Create charge.json"
    let theme = ThemeEnvironment(catalog: ThemeCatalog.load(), isDark: false)

    func example(_ n: Int, name: String = "ok", status: Int = 200) -> Example {
        Example(id: ExampleID(UUID(uuidString: "00000000-0000-4000-8000-00000000E\(String(format: "%03d", n))")!),
                name: name, status: status, body: .text("{\"n\": \(n)}"))
    }

    /// The Request file as someone else leaves it.
    func put(_ examples: [Example], definition: RequestDefinition = OpenRequestTests.charge.definition) throws {
        try FileManager.default.createDirectory(at: base.file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try RequestFile.encode(Request(id: request, name: "Create charge", definition: definition, examples: examples)).write(to: base.file)
    }

    func onDisk() throws -> Request { try RequestFile.decode(Data(contentsOf: base.file)) }

    /// A window over a file with Examples 1 and 2.
    func makeWindow(_ examples: [Example]? = nil) throws -> WindowModel {
        try put(examples ?? [example(1), example(2)])
        let window = base.makeWindow()
        window.loadDataFolder()
        return window
    }

    func openFirst() throws -> (WindowModel, TabModel) {
        let window = try makeWindow()
        window.openExample(request, example(1).id)
        return (window, try #require(window.selectedTab))
    }

    func deliver(_ paths: [String], to window: WindowModel) async {
        let before = window.scanCount
        base.watch.emit(paths)
        for _ in 0..<200 where window.scanCount == before { await Task.yield() }
    }

    func settle() async {
        for _ in 0..<10 { await Task.yield() }
    }

    // MARK: openExample

    @Test func `opening an Example adds a clean Tab for it after the selected one, selected`() throws {
        let window = try makeWindow()
        let draft = window.tabs[0].tab.id

        window.openExample(request, example(2).id)

        #expect(window.tabs.count == 2)
        let tab = window.tabs[1].tab
        #expect(tab.source == .example(request, example(2).id))
        #expect(tab.content == .example(example(2)))
        #expect(tab.baseline == .example(example(2)))
        #expect(!tab.isDirty)
        #expect(window.selected == tab.id)
        #expect(window.tabs[0].tab.id == draft)
    }

    @Test func `opening the same Example twice selects the same Tab`() throws {
        let window = try makeWindow()
        window.openExample(request, example(1).id)
        let opened = try #require(window.selected)
        window.select(window.tabs[0].tab.id)

        window.openExample(request, example(1).id)

        #expect(window.tabs.count == 2)
        #expect(window.selected == opened)
    }

    @Test func `an Example and its Request, and two Examples, are Tabs of their own`() throws {
        let window = try makeWindow()

        window.openRequest(request)
        window.openExample(request, example(1).id)
        window.openExample(request, example(2).id)
        window.openRequest(request)
        window.openExample(request, example(2).id)

        #expect(window.tabs.map(\.tab.source) == [.draft, .request(request), .example(request, example(1).id), .example(request, example(2).id)])
    }

    @Test func `an Example the file lost since the scan opens no Tab, and neither does a Request that is not there`() throws {
        let window = try makeWindow()
        try put([example(2)])

        window.openExample(request, example(1).id)
        window.openExample(RequestID(UUID()), example(1).id)

        #expect(window.tabs.count == 1)
        #expect(window.index.collections[0].nodes == [
            .request(request, name: "Create charge", method: "POST", path: path, examples: [ExampleSummary(example(2))]),
        ])
    }

    @Test func `a file that broke since the scan opens no Example Tab`() throws {
        let window = try makeWindow()
        try Data("{ broken".utf8).write(to: base.file)

        window.openExample(request, example(1).id)

        #expect(window.tabs.count == 1)
    }

    @Test func `an Example Tab is named by its working copy, so a rename in the pane shows`() throws {
        let (window, tab) = try openFirst()
        #expect(window.name(of: tab.tab) == "ok")

        tab.tab.content = .example(example(1, name: "renamed"))

        #expect(window.name(of: tab.tab) == "renamed")
    }

    @Test func `two Tabs for one Example is a bug, and relaunch dies on it`() async throws {
        await #expect(processExitsWith: .failure) {
            await MainActor.run {
                let temp = FileManager.default.temporaryDirectory.appending(path: "raccoon-\(UUID())")
                let store = DiskSessionStore(directory: temp, root: temp.appending(path: "Raccoon").path)
                let file = temp.appending(path: "Raccoon/C/R.json")
                let (id, exampleID) = (RequestID(UUID()), ExampleID(UUID()))
                let one = Example(id: exampleID, name: "ok", status: 200, body: .text(""))
                try! FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
                try! RequestFile.encode(Request(id: id, name: "R", definition: .empty, examples: [one])).write(to: file)
                let tabs = (0..<2).map { _ in
                    TabSnapshot(id: TabID(UUID()), source: .example(id, exampleID), content: .example(one), baseline: .example(one))
                }
                try! store.write(SessionFile.encode(Session(tabs: tabs, selected: nil, activeEnvironment: nil)))
                let window = WindowModel(
                    dataFolder: .test(temp.appending(path: "Raccoon")), folderWatch: ManualFolderWatch(), sessionStore: store,
                    secrets: InMemorySecretStore(), instants: FixedInstantSource(.now),
                    makeTab: {
                        TabModel(transport: ScriptedTransport(.failure(.timedOut(seconds: 60))), secrets: InMemorySecretStore(), files: DictionaryFileReading([:]),
                                 instants: FixedInstantSource(.now), clipboard: RecordingClipboardWriter())
                    }
                )
                window.loadDataFolder()
                window.relaunch()
            }
        }
    }

    // MARK: ⌘S

    @Test func `saving an Example Tab writes the Example and keeps the definition and the others`() throws {
        let (window, tab) = try openFirst()
        tab.tab.content = .example(example(1, name: "changed", status: 500))
        #expect(tab.tab.isDirty)

        window.save(tab.tab.id)

        #expect(try onDisk().examples == [example(1, name: "changed", status: 500), example(2)])
        #expect(try onDisk().definition == OpenRequestTests.charge.definition)
        #expect(!tab.tab.isDirty)
        #expect(tab.tab.baseline == tab.tab.content)
        #expect(tab.notice == nil)
        #expect(window.ledger.isOurs(path, try Data(contentsOf: base.file)))
    }

    @Test func `saving an Example Tab leaves its Request Tab's edits alone`() throws {
        let window = try makeWindow()
        window.openRequest(request)
        let requestTab = try #require(window.selectedTab)
        requestTab.tab.definition.headers.append(Row(name: "X-Mine", value: "1"))
        window.openExample(request, example(1).id)
        let tab = try #require(window.selectedTab)
        tab.tab.content = .example(example(1, name: "changed"))

        window.save(tab.tab.id)

        #expect(requestTab.tab.isDirty && !requestTab.tab.isChangedOnDisk)
        #expect(try onDisk().definition == OpenRequestTests.charge.definition)
    }

    @Test func `saving after the Request was deleted says so, writes nothing and stays Dirty`() async throws {
        let (window, tab) = try openFirst()
        tab.tab.content = .example(example(1, name: "changed"))
        try FileManager.default.removeItem(at: base.file)
        await deliver([path], to: window)

        window.save(tab.tab.id)

        #expect(tab.notice == .requestDeleted)
        #expect(tab.tab.isDirty)
        #expect(!FileManager.default.fileExists(atPath: base.file.path))
        #expect(TabBanner.content(notice: .requestDeleted, changedOnDisk: nil) == Banner(
            glyph: .error, lead: "Not saved.", detail: [.text(" Its Request was deleted.")], buttons: [TabBanner.dismiss]))
    }

    @Test func `saving into an unreadable file is Not saved with the file's name, and stays Dirty`() throws {
        let (window, tab) = try openFirst()
        tab.tab.content = .example(example(1, name: "changed"))
        let garbage = Data("not json".utf8)
        try garbage.write(to: base.file)

        window.save(tab.tab.id)

        guard case .notSaved(let file, _) = tab.notice else { Issue.record("no Not saved: \(String(describing: tab.notice))"); return }
        #expect(file == "Create charge.json")
        #expect(tab.tab.isDirty)
        #expect(try Data(contentsOf: base.file) == garbage)
    }

    // MARK: Changed on Disk

    @Test func `a clean Example Tab reloads silently when its Example changes on disk`() async throws {
        let (window, tab) = try openFirst()
        try put([example(1, name: "pulled", status: 201), example(2)])

        await deliver([path], to: window)

        #expect(tab.tab.content == .example(example(1, name: "pulled", status: 201)))
        #expect(tab.tab.baseline == tab.tab.content)
        #expect(!tab.tab.isChangedOnDisk && tab.notice == nil)
    }

    @Test func `a Dirty Example Tab keeps its edits and is Changed on Disk; Reload takes the file`() async throws {
        let (window, tab) = try openFirst()
        tab.tab.content = .example(example(1, name: "mine"))
        try put([example(1, name: "pulled"), example(2)])

        await deliver([path], to: window)

        #expect(tab.tab.content == .example(example(1, name: "mine")))
        #expect(tab.tab.baseline == .example(example(1, name: "pulled")))
        #expect(tab.tab.isChangedOnDisk)
        let binding = TabBannerBinding(window: window, theme: theme, reduceMotion: { true })
        #expect(binding.view.content?.buttons.map(\.title) == ["Keep Mine", "Reload"])
        #expect(window.fileName(of: tab.tab) == "Create charge.json")

        window.reload(tab.tab.id)
        #expect(tab.tab.content == .example(example(1, name: "pulled")))
        #expect(!tab.tab.isChangedOnDisk && !tab.tab.isDirty)
    }

    @Test func `an Example Tab is left alone when another Example of its Request changes`() async throws {
        let (window, tab) = try openFirst()
        tab.tab.content = .example(example(1, name: "mine"))
        let before = tab.tab
        try put([example(1), example(2, name: "pulled")])

        await deliver([path], to: window)

        #expect(tab.tab == before)
    }

    @Test func `a change to the definition alone never touches an Example Tab, and Examples alone never a Request Tab`() async throws {
        let window = try makeWindow()
        window.openRequest(request)
        let requestTab = try #require(window.selectedTab)
        window.openExample(request, example(1).id)
        let exampleTab = try #require(window.selectedTab)
        let (requestBefore, exampleBefore) = (requestTab.tab, exampleTab.tab)

        var pulled = OpenRequestTests.charge.definition
        pulled.url = "https://api.example.com/v2/charges"
        try put([example(1), example(2)], definition: pulled)
        await deliver([path], to: window)
        #expect(exampleTab.tab == exampleBefore)
        #expect(requestTab.tab.definition == pulled)

        try put([example(1, name: "pulled"), example(2)], definition: pulled)
        await deliver([path], to: window)
        #expect(requestTab.tab.definition == pulled && requestTab.tab.baseline == .request(pulled) && !requestTab.tab.isChangedOnDisk)
        #expect(requestBefore.id == requestTab.tab.id)
        #expect(exampleTab.tab.content == .example(example(1, name: "pulled")))
    }

    @Test func `an Example gone from the file is Deleted on disk, stays an Example Tab, and ⌘S appends it again`() async throws {
        let (window, tab) = try openFirst()
        tab.tab.content = .example(example(1, name: "mine"))
        try put([example(2)])

        await deliver([path], to: window)

        #expect(tab.tab.source == .example(request, example(1).id))
        #expect(tab.tab.content == .example(example(1, name: "mine")))
        #expect(tab.tab.baseline == nil && tab.tab.isDirty)
        #expect(tab.notice == .exampleDeletedOnDisk)
        #expect(!tab.tab.isChangedOnDisk)

        window.save(tab.tab.id)

        #expect(try onDisk().examples == [example(2), example(1, name: "mine")])
        #expect(tab.notice == nil && !tab.tab.isDirty)
    }

    @Test func `a Request deleted under an Example Tab is Deleted on disk, and ⌘S is Not saved`() async throws {
        let (window, tab) = try openFirst()
        try FileManager.default.removeItem(at: base.file)

        await deliver([path], to: window)

        #expect(tab.tab.source == .example(request, example(1).id))
        #expect(tab.tab.baseline == nil)
        #expect(tab.notice == .exampleDeletedOnDisk)

        window.save(tab.tab.id)
        #expect(tab.notice == .requestDeleted)
        #expect(tab.tab.isDirty)
    }

    @Test func `removing an Example from the sidebar turns its open Tab into Deleted on disk`() throws {
        let (window, tab) = try openFirst()
        let other = try #require(window.tabs.first)

        try window.removeExample(request, example(1).id)

        #expect(tab.tab.baseline == nil && tab.notice == .exampleDeletedOnDisk)
        #expect(other.notice == nil)
    }

    @Test func `renaming an Example from the sidebar updates its clean Tab, and a Dirty one is Changed on Disk`() throws {
        let window = try makeWindow()
        window.openExample(request, example(1).id)
        let clean = try #require(window.selectedTab)
        window.openExample(request, example(2).id)
        let dirty = try #require(window.selectedTab)
        dirty.tab.content = .example(example(2, name: "mine"))

        try window.updateExample(request, example(1).id) { $0.name = "renamed" }
        try window.updateExample(request, example(2).id) { $0.name = "renamed too" }

        #expect(clean.tab.content == .example(example(1, name: "renamed")) && !clean.tab.isChangedOnDisk)
        #expect(dirty.tab.content == .example(example(2, name: "mine")) && dirty.tab.isChangedOnDisk)
    }

    // MARK: Session

    func store() -> DiskSessionStore {
        DiskSessionStore(directory: base.temp.appending(path: "Support"), root: base.root.path)
    }

    @Test func `a Dirty Example Tab round-trips through the Session and relaunch`() throws {
        let (window, tab) = try openFirst()
        tab.tab.content = .example(example(1, name: "mine"))
        try store().write(SessionFile.encode(window.session))

        let relaunched = base.makeWindow()
        relaunched.loadDataFolder()

        let restored = try #require(relaunched.tabs.first { $0.tab.id == tab.tab.id })
        #expect(restored.tab.source == .example(request, example(1).id))
        #expect(restored.tab.content == .example(example(1, name: "mine")))
        #expect(restored.tab.baseline == .example(example(1)))
        #expect(restored.tab.isDirty && !restored.tab.isChangedOnDisk)
    }

    @Test func `relaunch against a changed Example: clean takes the file, Dirty is Changed on Disk`() throws {
        let (window, tab) = try openFirst()
        let cleanSession = window.session
        tab.tab.content = .example(example(1, name: "mine"))
        let dirtySession = window.session
        try put([example(1, name: "pulled"), example(2)])

        try store().write(SessionFile.encode(cleanSession))
        let clean = base.makeWindow()
        clean.loadDataFolder()
        let cleanTab = try #require(clean.tabs.first { $0.tab.id == tab.tab.id })
        #expect(cleanTab.tab.content == .example(example(1, name: "pulled")) && cleanTab.tab.baseline == cleanTab.tab.content)

        try store().write(SessionFile.encode(dirtySession))
        let dirty = base.makeWindow()
        dirty.loadDataFolder()
        let dirtyTab = try #require(dirty.tabs.first { $0.tab.id == tab.tab.id })
        #expect(dirtyTab.tab.content == .example(example(1, name: "mine")))
        #expect(dirtyTab.tab.baseline == .example(example(1, name: "pulled")) && dirtyTab.tab.isChangedOnDisk)
    }

    @Test func `relaunch with the Example or its Request gone: still an Example Tab, Deleted on disk`() throws {
        let (window, tab) = try openFirst()
        tab.tab.content = .example(example(1, name: "mine"))
        try store().write(SessionFile.encode(window.session))

        for examples in [[example(2)], nil] {
            if let examples { try put(examples) } else { try FileManager.default.removeItem(at: base.file) }
            let relaunched = base.makeWindow()
            relaunched.loadDataFolder()

            let restored = try #require(relaunched.tabs.first { $0.tab.id == tab.tab.id })
            #expect(restored.tab.source == .example(request, example(1).id))
            #expect(restored.tab.content == .example(example(1, name: "mine")))
            #expect(restored.tab.baseline == nil)
            #expect(restored.notice == .exampleDeletedOnDisk)
        }
    }

    // MARK: Duplicate, Close, Send

    @Test func `Duplicate Tab is refused for an Example Tab, and not offered in its menu`() throws {
        let (window, tab) = try openFirst()
        let strip = TabStripView(window: window, theme: theme)

        window.duplicate(tab.tab.id)

        #expect(window.tabs.count == 2)
        #expect(strip.contextMenu(for: tab).items.first { $0.title == "Duplicate Tab" }?.isEnabled == false)
        #expect(strip.contextMenu(for: window.tabs[0]).items.first { $0.title == "Duplicate Tab" }?.isEnabled == true)
    }

    @Test func `closing a Dirty Example Tab asks, a clean one does not, and Force Close never does`() throws {
        let (window, tab) = try openFirst()
        let ask = CloseTabTests.ScriptedAsk(.cancel)
        let closer = TabCloser(window: window, saver: DraftSaver(window: window, ask: { _, _, reply in reply(nil) }, focusURL: {}),
                               memory: CloseMemory(), confirmForce: { _, reply in reply(true) }, ask: ask.ask)

        closer.close(tab)
        #expect(ask.asked.isEmpty)
        #expect(!window.tabs.contains { $0 === tab })

        window.openExample(request, example(2).id)
        let dirty = try #require(window.selectedTab)
        dirty.tab.content = .example(example(2, name: "mine"))
        closer.close(dirty)
        #expect(ask.asked == [dirty.tab.id])
        #expect(window.tabs.contains { $0 === dirty })

        closer.close(.tab, of: dirty, force: true)
        #expect(ask.asked == [dirty.tab.id])
        #expect(!window.tabs.contains { $0 === dirty })
    }

    @Test func `Save in the close sheet writes the Example and then closes`() throws {
        let (window, tab) = try openFirst()
        tab.tab.content = .example(example(1, name: "mine"))
        let ask = CloseTabTests.ScriptedAsk(.save)
        let closer = TabCloser(window: window, saver: DraftSaver(window: window, ask: { _, _, reply in reply(nil) }, focusURL: {}),
                               memory: CloseMemory(), confirmForce: { _, reply in reply(true) }, ask: ask.ask)

        closer.close(tab)

        #expect(!window.tabs.contains { $0 === tab })
        #expect(try onDisk().examples.first?.name == "mine")
    }

    @Test func `an Example Tab sends nothing and copies no curl`() throws {
        let (_, tab) = try openFirst()

        tab.send()

        #expect(tab.inFlight == nil && tab.tab.response == .idle)
        #expect(tab.curl(includeSecrets: false).isFailure)
    }

    // MARK: Sidebar and Breadcrumb

    @Test func `clicking or activating an Example row in the sidebar opens its Tab`() throws {
        let window = try makeWindow()
        let sidebar = SidebarViewController(window: window, theme: theme, reveal: { _ in })
        sidebar.view.frame = NSRect(x: 0, y: 0, width: 232, height: 600)
        sidebar.outline.expandItem(nil, expandChildren: true)

        sidebar.open(row: 3)
        #expect(window.selectedTab?.tab.source == .example(request, example(2).id))

        sidebar.activate(row: 2)
        #expect(window.selectedTab?.tab.source == .example(request, example(1).id))
        #expect(window.tabs.count == 3)
    }

    @Test func `the Breadcrumb of an Example Tab ends with the Example's name, and follows a rename`() async throws {
        let (window, tab) = try openFirst()
        let binding = BreadcrumbBinding(window: window, theme: theme, select: { _ in })
        binding.bar.frame = NSRect(x: 0, y: 0, width: 900, height: BreadcrumbBar.height)
        binding.bar.layoutSubtreeIfNeeded()
        #expect(binding.bar.visibleCrumbs.map(\.title) == ["Payments API", "Create charge", "ok"])

        tab.tab.content = .example(example(1, name: "renamed"))
        await settle()
        binding.bar.layoutSubtreeIfNeeded()
        #expect(binding.bar.visibleCrumbs.map(\.title) == ["Payments API", "Create charge", "renamed"])
    }

    @Test func `the Example Tab's strip title and its Deleted on disk banner`() throws {
        let (window, _) = try openFirst()
        let strip = TabStripView(window: window, theme: theme)
        strip.frame = NSRect(x: 0, y: 0, width: 1_000, height: TabStripView.height)
        strip.layoutSubtreeIfNeeded()

        #expect(strip.items[1].name.stringValue == "ok")
        #expect(TabBanner.content(notice: .exampleDeletedOnDisk, changedOnDisk: nil)?.lead == "Deleted on disk.")
    }

    @Test func `an Example Tab shows no editor in the content area`() throws {
        let (window, tab) = try openFirst()
        let content = ContentViewController(strip: TabStripView(window: window, theme: theme),
                                            breadcrumb: BreadcrumbBinding(window: window, theme: theme, select: { _ in }),
                                            tab: TabViewController(model: tab, theme: theme),
                                            banner: TabBannerBinding(window: window, theme: theme, reduceMotion: { true }),
                                            emptyState: EmptyStateView(theme: theme, menu: nil))
        content.view.frame = NSRect(x: 0, y: 0, width: 900, height: 600)

        content.showsTab(true, editor: false)
        #expect(content.tab.view.isHidden && !content.breadcrumb.bar.isHidden)

        content.showsTab(true, editor: true)
        #expect(!content.tab.view.isHidden)
    }
}

private extension Result {
    var isFailure: Bool { if case .failure = self { true } else { false } }
}

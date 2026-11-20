import AppKit
import Observation
import RaccoonDomain

/// One sidebar row: the outline needs objects, and the path names the row across reloads,
/// so expansion survives a rescan and is autosaved by path.
final class SidebarItem {
    enum Kind: Equatable {
        case collection
        case folder
        case request(RequestID, method: String)
        /// A child of a Request row. Selectable, and inert: nothing opens from it yet.
        case example(RequestID, ExampleID, status: Int)
        case unreadable(reason: String)
    }

    let kind: Kind
    let name: String
    /// A Collection's name, a Folder's path, a file's path: relative to the Data Folder.
    let path: String
    let children: [SidebarItem]

    init(kind: Kind, name: String, path: String, children: [SidebarItem] = []) {
        self.kind = kind
        self.name = name
        self.path = path
        self.children = children
    }

    var isExample: Bool { if case .example = kind { true } else { false } }

    /// This row's own path, or one below it.
    func contains(_ path: String) -> Bool {
        self.path == path || children.contains { $0.contains(path) }
    }

    static func tree(_ collections: [Collection]) -> [SidebarItem] {
        func items(_ nodes: [TreeNode], in parent: String) -> [SidebarItem] {
            nodes.map { node in
                switch node {
                case .folder(let name, let children):
                    SidebarItem(kind: .folder, name: name, path: parent + "/" + name, children: items(children, in: parent + "/" + name))
                case .request(let id, let name, let method, let path, let examples):
                    SidebarItem(kind: .request(id, method: method), name: name, path: path, children: examples.map {
                        SidebarItem(kind: .example(id, $0.id, status: $0.status), name: $0.name, path: $0.path(in: path))
                    })
                case .unreadable(let path, let reason):
                    SidebarItem(kind: .unreadable(reason: reason), name: node.name, path: path)
                }
            }
        }
        return collections.map { SidebarItem(kind: .collection, name: $0.name, path: $0.name, children: items($0.nodes, in: $0.name)) }
    }
}

/// The sidebar (design-system §6 Sidebar rows): native chrome on the opaque window background,
/// a source-list outline of the Data Folder, and the method badges in Theme colours. Lives
/// inside the sidebar pane's content view, so the narrow-window overlay borrows it whole.
final class SidebarViewController: NSViewController, NSOutlineViewDataSource, NSOutlineViewDelegate, NSMenuDelegate,
    NSMenuItemValidation, NSSearchFieldDelegate {
    /// The open Workspace and the others, above the filter (design-system §6 Workspace pop-up).
    let workspacePopUp: WorkspacePopUp
    /// design-system §6 Sidebar filter: names only, every keystroke, no debounce.
    let searchField = NSSearchField()
    let sectionLabel = NSTextField(labelWithString: "Collections")
    /// Takes the section label's place while filtering: "4 matches in 1 Collection".
    let countLabel = NSTextField(labelWithString: "")
    let noMatches = NSTextField(wrappingLabelWithString: "")
    /// Gives focus to the selected Tab's URL field.
    var focusEditor: () -> Void = {}
    private var query = ""
    private var expansionBeforeFilter: Set<String>?
    private var matches: [String: FilteredTree.Match] = [:]
    private var searchHeight: NSLayoutConstraint!
    /// The footer's + menu.
    let addMenu = NSMenu()
    let addButton = NSButton()

    /// The name sheet in the app: title, current name, confirm button, and nil on Cancel.
    var askName: (_ title: String, _ name: String, _ button: String, _ reply: @escaping (String?) -> Void) -> Void = { _, _, _, reply in reply(nil) }
    /// The open panel for one folder (Open Workspace…), nil on Cancel.
    var chooseWorkspaceFolder: () async -> String? = { nil }
    /// The save panel for a new folder's name and place (New Workspace…), nil on Cancel.
    var chooseNewWorkspace: () async -> String? = { nil }
    /// An alert sheet in the app, for an operation that failed.
    var showError: (String) -> Void = { _ in }
    /// The confirmation before an Example is deleted: its name, and whether to go on. No answer means no.
    var confirmDeleteExample: (_ name: String, _ reply: @escaping (Bool) -> Void) -> Void = { _, reply in reply(false) }
    /// The + menu's Import from Postman…: the app's open panel, then the Import sheet.
    var importFromPostman: () -> Void = {}
    /// A Collection row's Export…: the app's Collection Export sheet, for the Collection named.
    var exportCollection: (String) -> Void = { _ in }
    /// The pop-up's Manage Workspaces…: the Workspaces sheet.
    var manageWorkspaces: () -> Void = {}
    let outline = SidebarOutline()
    let empty = NSStackView()
    let emptyText = NSTextField(wrappingLabelWithString: "No Collections yet. Create one, or save a Draft into one with ⌘S.")
    let emptyPath = NSTextField(wrappingLabelWithString: "")

    private let window: WindowModel
    private let theme: ThemeEnvironment
    private let revealInFinder: (String) -> Void
    private var items: [SidebarItem] = []
    private var byPath: [String: SidebarItem] = [:]
    private var laidOutWidth: CGFloat = 0

    /// `reveal` gets an absolute path; NSWorkspace's file viewer in the app.
    init(window: WindowModel, theme: ThemeEnvironment, reveal: @escaping (String) -> Void) {
        self.window = window
        self.theme = theme
        self.revealInFinder = reveal
        workspacePopUp = WorkspacePopUp(theme: theme)
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 232, height: 600))

        sectionLabel.font = .systemFont(ofSize: 11, weight: .semibold)
        sectionLabel.textColor = .secondaryLabelColor
        countLabel.font = .systemFont(ofSize: 11)
        countLabel.textColor = .secondaryLabelColor
        noMatches.font = .systemFont(ofSize: 12)
        noMatches.textColor = .secondaryLabelColor
        searchField.placeholderString = "Filter Collections"
        searchField.setAccessibilityLabel("Filter Collections")
        searchField.sendsSearchStringImmediately = true
        searchField.delegate = self
        searchField.target = self
        searchField.action = #selector(searchChanged)

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("name"))
        outline.addTableColumn(column)
        outline.outlineTableColumn = column
        outline.headerView = nil
        outline.style = .sourceList
        outline.rowSizeStyle = .custom
        outline.rowHeight = 24
        outline.indentationPerLevel = 16
        outline.backgroundColor = .clear
        outline.dataSource = self
        outline.delegate = self
        outline.target = self
        outline.action = #selector(clicked)
        outline.doubleAction = #selector(doubleClicked)
        outline.setAccessibilityLabel("Collections")
        outline.menu = NSMenu()
        outline.menu?.delegate = self
        outline.onDelete = { [weak self] row in self?.deleteKey(row: row) }

        addMenu.addItem(NSMenuItem(title: "New Collection", action: #selector(newCollection(_:)), keyEquivalent: ""))
        addMenu.addItem(NSMenuItem(title: "New Folder", action: #selector(newFolder(_:)), keyEquivalent: ""))
        addMenu.addItem(.separator())
        addMenu.addItem(NSMenuItem(title: "Import from Postman…", action: #selector(importPostman), keyEquivalent: ""))
        addMenu.items.forEach { $0.target = self }
        addButton.image = NSImage(systemSymbolName: "plus", accessibilityDescription: "Add")
        addButton.bezelStyle = .accessoryBarAction
        addButton.isBordered = false
        addButton.toolTip = "New Collection or Folder"
        addButton.target = self
        addButton.action = #selector(showAddMenu)
        let scroll = NSScrollView()
        scroll.documentView = outline
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true

        emptyText.font = .systemFont(ofSize: 12)
        emptyText.textColor = .secondaryLabelColor
        emptyPath.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        emptyPath.textColor = .secondaryLabelColor
        emptyPath.lineBreakMode = .byCharWrapping
        empty.orientation = .vertical
        empty.alignment = .leading
        empty.spacing = 4
        empty.addArrangedSubview(emptyText)
        empty.addArrangedSubview(emptyPath)

        workspacePopUp.onSwitch = { [window] root in Task { await window.switchWorkspace(root) } }
        workspacePopUp.onManage = { [weak self] in self?.manageWorkspaces() }
        workspacePopUp.onOpen = { [weak self] in
            Task {
                guard let self, let root = await self.chooseWorkspaceFolder() else { return }
                await self.window.openWorkspace(root)
            }
        }
        workspacePopUp.onNew = { [weak self] in
            Task {
                guard let self, let root = await self.chooseNewWorkspace() else { return }
                if let message = await self.window.newWorkspace(root) { self.showError(message) }
            }
        }

        searchHeight = searchField.heightAnchor.constraint(equalToConstant: 24)
        for child in [workspacePopUp, searchField, sectionLabel, countLabel, scroll, empty, noMatches, addButton] as [NSView] {
            child.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(child)
        }
        NSLayoutConstraint.activate([
            workspacePopUp.topAnchor.constraint(equalTo: view.topAnchor, constant: 8),
            workspacePopUp.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 10),
            workspacePopUp.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -10),
            searchField.topAnchor.constraint(equalTo: workspacePopUp.bottomAnchor, constant: 6),
            searchField.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 10),
            searchField.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -10),
            searchHeight,
            sectionLabel.topAnchor.constraint(equalTo: searchField.bottomAnchor, constant: 8),
            sectionLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            countLabel.firstBaselineAnchor.constraint(equalTo: sectionLabel.firstBaselineAnchor),
            countLabel.leadingAnchor.constraint(equalTo: sectionLabel.leadingAnchor),
            noMatches.topAnchor.constraint(equalTo: sectionLabel.topAnchor),
            noMatches.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 18),
            noMatches.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -18),
            scroll.topAnchor.constraint(equalTo: sectionLabel.bottomAnchor, constant: 4),
            scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: addButton.topAnchor, constant: -6),
            addButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 10),
            addButton.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -6),
            addButton.widthAnchor.constraint(equalToConstant: 28),
            addButton.heightAnchor.constraint(equalToConstant: 28),
            empty.topAnchor.constraint(equalTo: sectionLabel.bottomAnchor, constant: 12),
            empty.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 18),
            empty.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -18),
        ])
        render()
        // After the first load: AppKit restores the saved expansion when these are set, by path.
        outline.autosaveExpandedItems = true
        outline.autosaveName = "Sidebar"
        theme.paint(self) { controller, _ in controller.repaintVisibleRows() }
    }

    /// Re-runs whenever the index or the root changes. Rows that were open stay open.
    private func render() {
        // mockServers is read here so a start or stop redraws the Collection rows' indicators.
        let (collections, root, workspaces, _) = withObservationTracking {
            (window.index.collections, window.dataFolderRoot, window.workspaces, window.mockServers)
        } onChange: { [weak self] in
            Task { @MainActor in self?.render() }
        }
        workspacePopUp.reload(workspaces: workspaces, open: root)
        var expanded = expansionBeforeFilter.map { _ in Set<String>() } ?? Set(byPath.values.filter { outline.isItemExpanded($0) }.map(\.path))
        let filtered = query.isEmpty ? nil : TreeFilter.matches(collections, query)
        if let filtered { expanded = filtered.expanded } else if let before = expansionBeforeFilter { expanded = before }
        matches = filtered?.matches ?? [:]
        items = SidebarItem.tree(filtered?.collections ?? collections)
        byPath = [:]
        func index(_ items: [SidebarItem]) { for item in items { byPath[item.path] = item; index(item.children) } }
        index(items)
        outline.reloadData()
        for path in expanded.sorted() { if let item = byPath[path] { outline.expandItem(item) } }

        emptyPath.stringValue = (root as NSString).abbreviatingWithTildeInPath
        let hasCollections = !collections.isEmpty
        searchField.isHidden = !hasCollections
        searchHeight.constant = hasCollections ? 24 : 0
        empty.isHidden = hasCollections
        sectionLabel.isHidden = filtered != nil
        countLabel.isHidden = filtered == nil || filtered?.matchCount == 0
        noMatches.isHidden = filtered?.matchCount != 0
        outline.enclosingScrollView?.isHidden = !hasCollections || filtered?.matchCount == 0
        if let filtered {
            countLabel.stringValue = Self.count(filtered)
            noMatches.stringValue = "No Requests, Folders or Collections match “\(query)”.\nEsc clears the filter."
        }
    }

    private static func count(_ filtered: FilteredTree) -> String {
        let number = { (n: Int) in n.formatted(.number.locale(Locale(identifier: "en"))) }
        let (n, c) = (filtered.matchCount, filtered.collections.count)
        return "\(number(n)) \(n == 1 ? "match" : "matches") in \(number(c)) \(c == 1 ? "Collection" : "Collections")"
    }

    // MARK: Filter

    /// ⌥⌘F. With no Collections the field is hidden and nothing takes focus.
    func focusFilter() {
        guard !searchField.isHidden else { return }
        view.window?.makeFirstResponder(searchField)
    }

    func controlTextDidChange(_ notification: Notification) {
        setQuery(searchField.stringValue)
    }

    @objc private func searchChanged() {
        setQuery(searchField.stringValue)
    }

    private func setQuery(_ text: String) {
        guard text != query else { return }
        if query.isEmpty {
            // The tree's own expansion comes back when the filter clears, and is not autosaved meanwhile.
            expansionBeforeFilter = Set(byPath.values.filter { outline.isItemExpanded($0) }.map(\.path))
            outline.autosaveExpandedItems = false
        }
        query = text
        if text.isEmpty {
            outline.collapseItem(nil, collapseChildren: true)
            render()
            expansionBeforeFilter = nil
            outline.autosaveExpandedItems = true
        } else {
            render()
        }
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        switch selector {
        case #selector(NSResponder.cancelOperation(_:)): cancel()
        case #selector(NSResponder.insertNewline(_:)): returnPressed()
        default: false
        }
    }

    /// Esc: clears a query; with none, gives focus back to the editor.
    @discardableResult
    func cancel() -> Bool {
        if query.isEmpty {
            focusEditor()
        } else {
            searchField.stringValue = ""
            setQuery("")
        }
        return true
    }

    /// Return: opens the selected match, else the first, and gives focus to the editor.
    @discardableResult
    func returnPressed() -> Bool {
        let isRequest = { (row: Int) in if case .request = (self.outline.item(atRow: row) as? SidebarItem)?.kind { true } else { false } }
        let row = isRequest(outline.selectedRow) ? outline.selectedRow : (0..<outline.numberOfRows).first(where: isRequest)
        if let row { open(row: row) }
        focusEditor()
        return true
    }

    private func repaintVisibleRows() {
        outline.enumerateAvailableRowViews { rowView, _ in
            (rowView.view(atColumn: 0) as? ThemedRow)?.paint(theme)
        }
    }

    /// The reason line wraps with the sidebar's width, so unreadable rows change height.
    override func viewDidLayout() {
        super.viewDidLayout()
        guard outline.bounds.width != laidOutWidth else { return }
        laidOutWidth = outline.bounds.width
        let rows = (0..<outline.numberOfRows).filter {
            if case .unreadable = (outline.item(atRow: $0) as? SidebarItem)?.kind { true } else { false }
        }
        if !rows.isEmpty { outline.noteHeightOfRows(withIndexesChanged: IndexSet(rows)) }
    }

    @objc private func clicked() {
        open(row: outline.clickedRow)
    }

    @objc private func doubleClicked() {
        if case .example? = (outline.item(atRow: outline.clickedRow) as? SidebarItem)?.kind {
            edit(row: outline.clickedRow)
        } else {
            activate(row: outline.clickedRow)
        }
    }

    /// A click: a Request opens in its Tab, an Example shows in its Request's Tab (examples.md §Show an
    /// Example). Anything else only selects.
    func open(row: Int) {
        guard let item = outline.item(atRow: row) as? SidebarItem else { return }
        switch item.kind {
        case .request(let id, _): window.openRequest(id)
        case .example(let requestID, let id, _): window.showExample(requestID, id)
        case .collection, .folder, .unreadable: break
        }
    }

    /// Double-click on an Example row: its editor Tab.
    func edit(row: Int) {
        guard case .example(let requestID, let id, _)? = (outline.item(atRow: row) as? SidebarItem)?.kind else { return }
        window.openExample(requestID, id)
    }

    /// Double-click or Return: a Request opens, an Example is shown, a Collection or Folder expands or collapses, an unreadable file is revealed in Finder.
    func activate(row: Int) {
        guard let item = outline.item(atRow: row) as? SidebarItem else { return }
        switch item.kind {
        case .request, .example: open(row: row)
        case .unreadable: revealInFinder(window.dataFolderRoot + "/" + item.path)
        case .collection, .folder:
            if outline.isItemExpanded(item) { outline.collapseItem(item) } else { outline.expandItem(item) }
        }
    }

    // MARK: New Collection, New Folder, rename, move, Move to Trash

    @objc private func showAddMenu() {
        addMenu.popUp(positioning: nil, at: NSPoint(x: 0, y: addButton.bounds.height + 4), in: addButton)
    }

    /// The Collection or Folder a row is, or is in.
    private func folder(of item: SidebarItem) -> String {
        switch item.kind {
        case .collection, .folder: item.path
        case .request, .unreadable, .example: String(item.path[..<(item.path.range(of: "/", options: .backwards)?.lowerBound ?? item.path.endIndex)])
        }
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        menuItem.action != #selector(newFolder(_:)) || outline.selectedRow >= 0
    }

    @objc func newCollection(_ sender: Any?) {
        askName("New Collection", "", "Create") { [weak self] name in
            guard let self, let name else { return }
            perform({ "Couldn't create “\(name)”: \($0)." }) { () throws(StoreError) in try self.window.newCollection(name) }
        }
    }

    @objc private func importPostman() {
        importFromPostman()
    }

    /// The row at a path in the tree now shown: a Collection's name, a Folder's or a file's path.
    func item(path: String) -> SidebarItem? { byPath[path] }

    /// Shows a location: a filter that would hide the row is cleared first, so the expansion from
    /// before it comes back, then every ancestor opens, the row is selected and scrolled into
    /// view. The row itself stays as it is, no Tab opens, nothing toggles and focus does not
    /// move: the selection is set in code, so the outline's click action does not run. False,
    /// with nothing changed, when no row has that path.
    @discardableResult
    func reveal(path: String) -> Bool {
        if item(path: path) == nil {
            // A tree rebuilt this turn may not have reached the outline yet; a filter may hide the row.
            if query.isEmpty { render() } else if SidebarItem.tree(window.index.collections).contains(where: { $0.contains(path) }) {
                searchField.stringValue = ""
                setQuery("")
            }
        }
        guard item(path: path) != nil else { return false }
        // From the tree, not the path: an Example's row sits under its Request's, which a path split would miss.
        for ancestor in Self.lineage(of: path, in: items).dropLast() { outline.expandItem(ancestor) }
        guard let item = item(path: path) else { return false }
        let row = outline.row(forItem: item)
        outline.selectRowIndexes([row], byExtendingSelection: false)
        outline.scrollRowToVisible(row)
        return true
    }

    /// The rows from a top one down to the row at `path`, outermost first; empty when no row has it.
    private static func lineage(of path: String, in items: [SidebarItem]) -> [SidebarItem] {
        guard let top = items.first(where: { $0.contains(path) }) else { return [] }
        return [top] + (top.path == path ? [] : lineage(of: path, in: top.children))
    }

    /// After Postman Import: `reveal(path:)`, then focus in the outline.
    @discardableResult
    func select(path: String) -> Bool {
        guard reveal(path: path) else { return false }
        view.window?.makeFirstResponder(outline)
        return true
    }

    /// In the selected row's Collection or Folder.
    @objc func newFolder(_ sender: Any?) {
        guard let item = outline.item(atRow: outline.selectedRow) as? SidebarItem else { return }
        newFolder(in: folder(of: item))
    }

    private func newFolder(in parent: String) {
        askName("New Folder", "", "Create") { [weak self] name in
            guard let self, let name else { return }
            perform({ "Couldn't create “\(name)”: \($0)." }) { () throws(StoreError) in try self.window.newFolder(name, in: parent) }
        }
    }

    /// The row's context menu (collections.md, Where they are).
    func contextMenu(row: Int) -> NSMenu {
        let menu = NSMenu()
        fill(menu, row: row)
        return menu
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        guard menu === outline.menu else { return }
        menu.removeAllItems()
        fill(menu, row: outline.clickedRow)
    }

    private func fill(_ menu: NSMenu, row: Int) {
        guard let item = outline.item(atRow: row) as? SidebarItem else { return }
        func add(_ title: String, _ action: Selector, _ object: Any) {
            let entry = NSMenuItem(title: title, action: action, keyEquivalent: "")
            entry.target = self
            entry.representedObject = object
            menu.addItem(entry)
        }
        // An Example has no file: no Move, Trash or Reveal. Delete… is set apart, last.
        if item.isExample {
            add("Edit Example…", #selector(editExample), item)
            add("Rename…", #selector(renameItem), item)
            add("Duplicate", #selector(duplicateExample), item)
            menu.addItem(.separator())
            add("Delete…", #selector(deleteExample), item)
            return
        }
        add("New Folder…", #selector(newFolderHere), folder(of: item))
        if case .request = item.kind { add("New Example", #selector(newExample), item) }
        if case .unreadable = item.kind {} else { add("Rename…", #selector(renameItem), item) }
        if item.kind == .collection {
            add("Export…", #selector(exportItem), item)
            if let mock = window.mockServers[item.name] {
                add("Stop Mock Server", #selector(stopMockItem), item)
                add("Copy Mock URL", #selector(copyMockURL), item)
                add("Allow Browser Requests (CORS)", #selector(toggleMockCORS), item)
                menu.items.last?.state = mock.allowsCORS ? .on : .off
            } else {
                add("Start Mock Server", #selector(startMockItem), item)
            }
        }
        if item.kind != .collection {
            let parent = String(item.path[..<(item.path.range(of: "/", options: .backwards)?.lowerBound ?? item.path.startIndex)])
            let targets = window.index.folders.filter { $0 != parent && $0 != item.path && !$0.hasPrefix(item.path + "/") }
            let moveTo = NSMenuItem(title: "Move To", action: nil, keyEquivalent: "")
            moveTo.submenu = NSMenu()
            for target in targets {
                let entry = NSMenuItem(title: target.replacingOccurrences(of: "/", with: " ▸ "), action: #selector(moveItem), keyEquivalent: "")
                entry.target = self
                entry.representedObject = MoveTarget(item: item, folder: target)
                moveTo.submenu?.addItem(entry)
            }
            moveTo.isEnabled = !targets.isEmpty
            menu.addItem(moveTo)
        }
        menu.addItem(.separator())
        add("Move to Trash", #selector(trashItem), item)
        add("Reveal in Finder", #selector(revealItem), item)
    }

    private final class MoveTarget {
        let item: SidebarItem
        let folder: String
        init(item: SidebarItem, folder: String) { (self.item, self.folder) = (item, folder) }
    }

    @objc private func newFolderHere(_ sender: NSMenuItem) {
        if let parent = sender.representedObject as? String { newFolder(in: parent) }
    }

    @objc private func renameItem(_ sender: NSMenuItem) {
        guard let item = sender.representedObject as? SidebarItem else { return }
        askName("Rename", item.name, "Rename") { [weak self] name in
            guard let self, let name else { return }
            if case .example(let requestID, let id, _) = item.kind {
                performExample({ "Couldn't rename the Example “\(item.name)”: \($0)" }) { () throws(ExampleWriteError) in
                    try self.window.updateExample(requestID, id) { $0.name = name }
                }
            } else {
                perform({ "Couldn't rename “\(item.name)”: \($0)." }) { () throws(StoreError) in try self.window.rename(item.path, to: name) }
            }
        }
    }

    /// A Request row's New Example: its Tab opens, and the sidebar shows the new row selected.
    @objc private func newExample(_ sender: NSMenuItem) {
        guard let item = sender.representedObject as? SidebarItem, case .request(let id, _) = item.kind else { return }
        performExample({ "Couldn't create an Example: \($0)" }) { () throws(ExampleWriteError) in
            if let row = try self.window.newExample(id) { self.reveal(path: row) }
        }
    }

    /// The copy sits after the original and is selected; no Tab opens.
    @objc private func editExample(_ sender: NSMenuItem) {
        guard let item = sender.representedObject as? SidebarItem, case .example(let requestID, let id, _) = item.kind else { return }
        window.openExample(requestID, id)
    }

    @objc private func duplicateExample(_ sender: NSMenuItem) {
        guard let item = sender.representedObject as? SidebarItem, case .example(let requestID, let id, _) = item.kind else { return }
        performExample({ "Couldn't duplicate the Example “\(item.name)”: \($0)" }) { () throws(ExampleWriteError) in
            if let row = try self.window.duplicateExample(requestID, id) { self.reveal(path: row) }
        }
    }

    @objc private func deleteExample(_ sender: NSMenuItem) {
        if let item = sender.representedObject as? SidebarItem { confirmDelete(item) }
    }

    /// ⌫ and Forward Delete in the outline: an Example row asks to delete; no other row has a key for it.
    private func deleteKey(row: Int) {
        if let item = outline.item(atRow: row) as? SidebarItem { confirmDelete(item) }
    }

    private func confirmDelete(_ item: SidebarItem) {
        guard case .example(let requestID, let id, _) = item.kind else { return }
        confirmDeleteExample(item.name) { [weak self] confirmed in
            guard let self, confirmed else { return }
            performExample({ "Couldn't delete the Example “\(item.name)”: \($0)" }) { () throws(ExampleWriteError) in
                try self.window.removeExample(requestID, id)
            }
        }
    }

    @objc private func moveItem(_ sender: NSMenuItem) {
        guard let target = sender.representedObject as? MoveTarget else { return }
        perform({ "Couldn't move “\(target.item.name)”: \($0)." }) { () throws(StoreError) in
            try self.window.move(target.item.path, to: target.folder)
        }
    }

    @objc private func exportItem(_ sender: NSMenuItem) {
        guard let item = sender.representedObject as? SidebarItem else { return }
        exportCollection(item.name)
    }

    @objc private func startMockItem(_ sender: NSMenuItem) {
        guard let item = sender.representedObject as? SidebarItem else { return }
        startMock(item.name, onAnotherPort: false)
    }

    /// The remembered port first; a taken one asks, and Use Another Port starts again on a free one.
    private func startMock(_ collection: String, onAnotherPort: Bool) {
        Task {
            do throws(MockError) {
                try await window.startMock(collection, onAnotherPort: onAnotherPort)
            } catch {
                switch error {
                case .portInUse(let port):
                    guard let sheetWindow = view.window else { return }
                    MockPortInUseAlert.ask(port: port, in: sheetWindow) { [weak self] useAnother in
                        if useAnother { self?.startMock(collection, onAnotherPort: true) }
                    }
                case .failed(let reason):
                    showError("Couldn't start the Mock Server: \(reason.hasSuffix(".") ? reason : reason + ".")")
                }
            }
        }
    }

    @objc private func stopMockItem(_ sender: NSMenuItem) {
        if let item = sender.representedObject as? SidebarItem { window.stopMock(item.name) }
    }

    @objc private func copyMockURL(_ sender: NSMenuItem) {
        guard let item = sender.representedObject as? SidebarItem, let mock = window.mockServers[item.name] else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(mock.url, forType: .string)
    }

    @objc private func toggleMockCORS(_ sender: NSMenuItem) {
        guard let item = sender.representedObject as? SidebarItem, let mock = window.mockServers[item.name] else { return }
        window.setMockAllowsCORS(item.name, !mock.allowsCORS)
    }

    /// The Collection the selected row is, or is in: File ▸ Export Collection… exports it.
    var selectedCollection: String? {
        (outline.item(atRow: outline.selectedRow) as? SidebarItem).flatMap { $0.path.split(separator: "/").first.map(String.init) }
    }

    @objc private func trashItem(_ sender: NSMenuItem) {
        guard let item = sender.representedObject as? SidebarItem else { return }
        perform({ "Couldn't move “\(item.name)” to the Trash: \($0)." }) { () throws(StoreError) in try self.window.trash(item.path) }
    }

    @objc private func revealItem(_ sender: NSMenuItem) {
        guard let item = sender.representedObject as? SidebarItem else { return }
        revealInFinder(window.dataFolderRoot + "/" + item.path)
    }

    /// Runs an operation; a failure is an alert, and nothing changes.
    private func perform(_ failure: (String) -> String, _ operation: () throws(StoreError) -> Void) {
        do throws(StoreError) {
            try operation()
        } catch {
            switch error {
            case .unwritable(_, let reason), .unreadable(_, let reason), .undecodable(_, let reason): showError(failure(reason))
            }
        }
    }

    /// `perform` for an Example write: the same alert with the reason, and nothing changes.
    private func performExample(_ failure: (String) -> String, _ operation: () throws(ExampleWriteError) -> Void) {
        do throws(ExampleWriteError) {
            try operation()
        } catch {
            showError(failure(error.sentence))
        }
    }

    // MARK: Data source

    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        (item as? SidebarItem)?.children.count ?? items.count
    }

    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        (item as? SidebarItem)?.children[index] ?? items[index]
    }

    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        switch (item as? SidebarItem)?.kind {
        case .collection, .folder: true
        case .request: !((item as? SidebarItem)?.children.isEmpty ?? true)
        default: false
        }
    }

    func outlineView(_ outlineView: NSOutlineView, persistentObjectForItem item: Any?) -> Any? {
        (item as? SidebarItem)?.path
    }

    func outlineView(_ outlineView: NSOutlineView, itemForPersistentObject object: Any) -> Any? {
        (object as? String).flatMap { byPath[$0] }
    }

    // MARK: Delegate

    /// Typing a name selects its row; the cells keep no textField for the outline to read.
    func outlineView(_ outlineView: NSOutlineView, typeSelectStringFor tableColumn: NSTableColumn?, item: Any) -> String? {
        (item as? SidebarItem)?.name
    }

    func outlineView(_ outlineView: NSOutlineView, heightOfRowByItem item: Any) -> CGFloat {
        guard let item = item as? SidebarItem, case .unreadable(let reason) = item.kind else { return 24 }
        // A width no wider than the cell will be, so the row is never too short for its reason.
        let level = CGFloat(outlineView.level(forItem: item) + 1)
        return UnreadableCell.height(reason: reason, cellWidth: outlineView.bounds.width - level * outlineView.indentationPerLevel - 8)
    }

    func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        guard let item = item as? SidebarItem else { return nil }
        switch item.kind {
        case .collection, .folder:
            let cell = reuse(NodeCell.identifier) { NodeCell(target: self, action: #selector(moreClicked)) }
            cell.show(item, match: matches[item.path]?.ranges ?? [], mockURL: item.kind == .collection ? window.mockServers[item.name]?.url : nil)
            cell.paint(theme)
            return cell
        case .request(_, let method):
            let cell = reuse(RequestCell.identifier) { RequestCell(target: self, action: #selector(moreClicked)) }
            cell.show(name: item.name, badge: method, token: .method(method), match: matches[item.path]?.ranges ?? [], theme: theme)
            return cell
        case .example(_, _, let status):
            // The Request row's cell, with the status where the method sits.
            let cell: RequestCell = reuse(RequestCell.exampleIdentifier) { RequestCell(target: self, action: #selector(moreClicked)) }
            // The Response status line's own class-to-token rule.
            let token = StatusLine(status: status, elapsed: .zero, byteCount: 0).token
            cell.show(name: item.name, badge: "\(status)", token: token, match: matches[item.path]?.ranges ?? [], theme: theme)
            return cell
        case .unreadable(let reason):
            let cell = reuse(UnreadableCell.identifier) { UnreadableCell(target: self, action: #selector(revealClicked), moreAction: #selector(moreClicked)) }
            cell.show(name: item.name, reason: reason, match: matches[item.path]?.ranges ?? [], theme: theme)
            return cell
        }
    }

    private func reuse<Cell: NSView>(_ identifier: NSUserInterfaceItemIdentifier, make: () -> Cell) -> Cell {
        if let cell = outline.makeView(withIdentifier: identifier, owner: self) as? Cell { return cell }
        let cell = make()
        cell.identifier = identifier
        return cell
    }

    @objc private func revealClicked(_ sender: NSButton) {
        activate(row: outline.row(for: sender))
    }

    /// Opens a menu under a view; the app's, replaced where a test cannot run a menu's tracking loop.
    var presentMenu: (NSMenu, NSView) -> Void = { menu, view in
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: view.isFlipped ? view.bounds.maxY : view.bounds.minY), in: view)
    }

    /// The ⋯ button: the row's context menu under it. The selection stays where it was.
    @objc private func moreClicked(_ sender: NSButton) {
        let row = outline.row(for: sender)
        guard row >= 0 else { return }
        presentMenu(contextMenu(row: row), sender)
        (sender.superview as? MoreActionsCell)?.syncHover()
    }

    /// The ⋯ shows on the selected row: every cell lays out again to ask.
    func outlineViewSelectionDidChange(_ notification: Notification) {
        outline.enumerateAvailableRowViews { rowView, _ in (rowView.view(atColumn: 0) as? MoreActionsCell)?.needsLayout = true }
    }
}

/// The outline, with ⌫ and Forward Delete handed to the sidebar for the selected row.
final class SidebarOutline: NSOutlineView {
    var onDelete: (Int) -> Void = { _ in }

    /// A click on a ⋯ button that reaches past its cell into the row's inset would otherwise land on the row.
    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        let row = row(at: local)
        if row >= 0, let cell = view(atColumn: 0, row: row, makeIfNecessary: false) as? MoreActionsCell, !cell.more.isHidden,
           cell.more.bounds.contains(cell.more.convert(local, from: self)) {
            return cell.more
        }
        return super.hitTest(point)
    }

    override func keyDown(with event: NSEvent) {
        // 51 is delete, 117 forward delete; ⌘⌫, ⌥⌫, ⇧⌫ and ⌃⌫ are not this.
        let plain = event.modifierFlags.intersection(.deviceIndependentFlagsMask).isEmpty
        if plain, event.keyCode == 51 || event.keyCode == 117, selectedRow >= 0 { return onDelete(selectedRow) }
        super.keyDown(with: event)
    }
}

/// A row's name, with each run of the filter's match in the system find colour and semibold, so it is not
/// told by colour alone (design-system §6 Sidebar filter).
/// On a selected row in a focused outline the name takes the selected-text colour, as AppKit
/// would do for a registered textField.
private func highlighted(_ name: String, _ matches: [Range<String.Index>], color: NSColor, style: NSView.BackgroundStyle) -> NSAttributedString {
    let color = style == .emphasized ? NSColor.alternateSelectedControlTextColor : color
    // Without a paragraph style the label wraps: a name the button leaves no room for would put its end on a
    // second line the one-line field clips, instead of ending in "…".
    let style = NSMutableParagraphStyle()
    style.lineBreakMode = .byTruncatingTail
    let text = NSMutableAttributedString(string: name, attributes: [.font: NSFont.systemFont(ofSize: 13), .foregroundColor: color, .paragraphStyle: style])
    for range in matches {
        text.addAttributes([.font: NSFont.systemFont(ofSize: 13, weight: .semibold), .backgroundColor: NSColor.findHighlightColor],
                           range: NSRange(range, in: name))
    }
    return text
}

/// A row that takes Theme colours; repainted on every Flavor change.
private protocol ThemedRow {
    func paint(_ theme: ThemeEnvironment)
}

/// The More actions button: the ellipsis alone at rest, on a rounded pill while the pointer is over it or it is pressed.
final class MoreButton: NSButton {
    private var over = false { didSet { refresh() } }
    var onSelectedRow = false { didSet { refresh() } }
    override var isHighlighted: Bool { didSet { refresh() } }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = 5
        layer?.cornerCurve = .continuous
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways], owner: self))
    }

    override func mouseEntered(with event: NSEvent) { over = true }
    override func mouseExited(with event: NSEvent) { over = false }
    override func viewDidHide() { over = false }

    /// White on the selection, the label colour elsewhere: 18% on the pointer, 28% pressed.
    func refresh() {
        let base: NSColor = onSelectedRow ? .alternateSelectedControlTextColor : .labelColor
        let alpha: CGFloat = isHighlighted ? 0.28 : (over ? 0.18 : 0)
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = base.withAlphaComponent(alpha).cgColor
        }
    }

    override func viewDidChangeEffectiveAppearance() { refresh() }
}

/// A row's cell plus its More actions button (design-system §6 Sidebar rows): an 18 pt `ellipsis` button
/// at the trailing edge, 4 pt inside the selection highlight, shown while the pointer is over the cell and while the row is
/// selected. A click opens the row's context menu and leaves the selection alone, because the
/// button takes the mouse-down before the outline does. Names stop `moreReserve` short of the edge.
class MoreActionsCell: NSTableCellView {
    static let moreSide: CGFloat = 18
    /// The source-list style draws the selection 10 pt in from the outline's edge, not at it.
    static let selectionInset: CGFloat = 10
    /// The space between the button and the selection's edge. The button sits inside the highlight, not on its edge.
    private static let moreInset: CGFloat = 4
    /// Where the button's trailing edge is, measured in from the outline's.
    private static let moreEdge = selectionInset + moreInset
    let more = MoreButton()
    var hovered = false { didSet { needsLayout = true } }

    init(target: AnyObject, action: Selector) {
        super.init(frame: .zero)
        more.image = NSImage(systemSymbolName: "ellipsis", accessibilityDescription: "More actions")?
            .withSymbolConfiguration(.init(pointSize: 12, weight: .regular))
        more.isBordered = false
        more.imagePosition = .imageOnly
        more.toolTip = "More actions"
        more.setAccessibilityLabel("More actions")
        more.target = target
        more.action = action
        more.isHidden = true
        addSubview(more)
        // The button reaches past the cell's edge into the row's inset.
        clipsToBounds = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    var isRowSelected: Bool { (superview as? NSTableRowView)?.isSelected ?? false }
    var showsMore: Bool { hovered || isRowSelected }
    /// What the source-list style leaves empty between the cell's trailing edge and the outline's. The button sits
    /// 14 pt in from the outline's edge (4 pt inside the selection), so it may reach into this space; a cell outside an outline has none.
    /// Measured against the outline, not the cell's parent: a selected row may wrap its cell in a narrower view,
    /// and the button would then sit left of the other rows'.
    var trailingInset: CGFloat {
        var view = superview
        while let current = view, !(current is NSTableView) { view = current.superview }
        guard let table = view else { return 0 }
        return max(0, table.bounds.width - convert(NSPoint(x: bounds.maxX, y: 0), to: table).x)
    }
    /// The width the cell gives up to the button, and a 4 pt gap, while it shows: what the inset does not already hold.
    var moreReserve: CGFloat { showsMore ? max(0, Self.moreEdge + Self.moreSide + 4 - trailingInset) : 0 }
    /// The cell and the space the button reaches into, so moving onto the button is still hovering the row.
    private var hoverRect: NSRect { NSRect(x: 0, y: 0, width: bounds.width + trailingInset, height: bounds.height) }

    /// AppKit calls this when the cell's geometry changes. Never from `layout()`: a layout runs on every hover change,
    /// and replacing the area while the pointer is inside it drops the exit event and leaves the row hovered for good.
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: hoverRect, options: [.mouseEnteredAndExited, .activeAlways], owner: self))
    }

    /// Hovered is where the pointer is now: a menu's tracking loop and a reload both hide the enter and exit events.
    func syncHover() {
        guard let window else { return hovered = false }
        hovered = hoverRect.contains(convert(window.mouseLocationOutsideOfEventStream, from: nil))
    }

    override func mouseEntered(with event: NSEvent) { hovered = true }
    override func mouseExited(with event: NSEvent) { hovered = false }
    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        needsLayout = true
    }

    /// The cell is put in its row before the row is in the outline, so the first layout may not know the inset.
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        needsLayout = true
        updateTrackingAreas()
    }

    private var laidOutInset: CGFloat = 0

    /// Whatever moved the cell since its last layout (a selected row's wrapper, a resize), the button is placed
    /// from the inset as it is now, before anything is drawn.
    override func viewWillDraw() {
        if trailingInset != laidOutInset { needsLayout = true }
        super.viewWillDraw()
    }

    override var backgroundStyle: NSView.BackgroundStyle { didSet { needsLayout = true } }

    /// A name cut short, by the edge or by the button, shows in full as a tooltip; one that fits shows none.
    func tipIfCut(_ field: NSTextField) {
        field.toolTip = (field.cell?.cellSize.width ?? 0) > field.frame.width ? field.stringValue : nil
    }

    /// Subclasses lay out after `super`, and read `moreReserve` for the width their name keeps.
    override func layout() {
        super.layout()
        laidOutInset = trailingInset
        more.isHidden = !showsMore
        more.contentTintColor = backgroundStyle == .emphasized ? .alternateSelectedControlTextColor : .secondaryLabelColor
        more.onSelectedRow = backgroundStyle == .emphasized
        let y = isFlipped ? 4 : ((bounds.height - Self.moreSide) / 2).rounded()
        more.frame = NSRect(x: bounds.width + trailingInset - Self.moreEdge - Self.moreSide, y: y, width: Self.moreSide, height: Self.moreSide)
    }
}

/// A Collection or Folder: its glyph and name in system colours.
final class NodeCell: MoreActionsCell, ThemedRow {
    static let identifier = NSUserInterfaceItemIdentifier("node")
    let glyph = NSImageView()
    let name = NSTextField(labelWithString: "")
    /// The Mock indicator: shown on a Collection whose Mock Server runs (design-system §6 Sidebar rows).
    let mockDot = NSView()
    private static let dotSide: CGFloat = 8
    private var dotColor = NSColor.systemGreen

    override init(target: AnyObject, action: Selector) {
        super.init(target: target, action: action)
        glyph.contentTintColor = .secondaryLabelColor
        name.font = .systemFont(ofSize: 13)
        name.lineBreakMode = .byTruncatingTail
        mockDot.wantsLayer = true
        mockDot.layer?.cornerRadius = Self.dotSide / 2
        mockDot.isHidden = true
        mockDot.setAccessibilityElement(true)
        mockDot.setAccessibilityRole(.image)
        // Not registered as textField: a source-list outline restyles that and drops the highlight.
        addSubview(glyph)
        addSubview(name)
        addSubview(mockDot)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// `mockURL` is the running Mock Server's address, nil when none runs.
    func show(_ item: SidebarItem, match: [Range<String.Index>], mockURL: String? = nil) {
        let symbol = item.kind == .collection ? "square.3.layers.3d" : "folder"
        glyph.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?.withSymbolConfiguration(.init(pointSize: 12, weight: .regular))
        shown = (item.name, match)
        let tip = mockURL.map { "Mock Server on \($0)" }
        mockDot.isHidden = tip == nil
        mockDot.toolTip = tip
        mockDot.setAccessibilityLabel(tip)
        syncHover()
        renderName()
        needsLayout = true
    }

    func paint(_ theme: ThemeEnvironment) {
        dotColor = theme.color(.success)
        renderDot()
    }

    /// The `success` colour, or the selected-text colour on an emphasized selection, as the badges do.
    private func renderDot() {
        let color = backgroundStyle == .emphasized ? NSColor.alternateSelectedControlTextColor : dotColor
        effectiveAppearance.performAsCurrentDrawingAppearance { mockDot.layer?.backgroundColor = color.cgColor }
    }

    override func viewDidChangeEffectiveAppearance() { renderDot() }

    private var shown: (String, [Range<String.Index>]) = ("", [])
    override var backgroundStyle: NSView.BackgroundStyle {
        didSet {
            renderName()
            renderDot()
            glyph.contentTintColor = backgroundStyle == .emphasized ? .alternateSelectedControlTextColor : .secondaryLabelColor
        }
    }
    private func renderName() { name.attributedStringValue = highlighted(shown.0, shown.1, color: .labelColor, style: backgroundStyle) }

    override func layout() {
        super.layout()
        glyph.frame = NSRect(x: 0, y: (bounds.height - 14) / 2, width: 14, height: 14)
        let height = name.cell?.cellSize.height ?? 16
        // The dot keeps its place whether or not the button shows, 4 pt before the button's slot; the name stops 4 pt short of it.
        let dotX = more.frame.minX - 4 - Self.dotSide
        mockDot.frame = NSRect(x: dotX, y: ((bounds.height - Self.dotSide) / 2).rounded(), width: Self.dotSide, height: Self.dotSide)
        let nameEnd = mockDot.isHidden ? bounds.width - moreReserve : min(bounds.width - moreReserve, dotX - 4)
        name.frame = NSRect(x: 20, y: ((bounds.height - height) / 2).rounded(), width: max(0, nameEnd - 20), height: height)
        tipIfCut(name)
    }
}

/// A Request: the left-aligned method badge, then the name 4 pt after it. An Example is the same
/// row with its status code as the badge.
final class RequestCell: MoreActionsCell, ThemedRow {
    static let identifier = NSUserInterfaceItemIdentifier("request")
    static let exampleIdentifier = NSUserInterfaceItemIdentifier("example")
    let badge = NSTextField(labelWithString: "")
    let name = NSTextField(labelWithString: "")
    private var badgeText = ""
    private var token = ColorToken.text
    private var badgeColor = NSColor.labelColor

    override init(target: AnyObject, action: Selector) {
        super.init(target: target, action: action)
        badge.alignment = .left
        badge.lineBreakMode = .byTruncatingTail
        badge.font = .monospacedSystemFont(ofSize: 9.5, weight: .bold)
        name.font = .systemFont(ofSize: 13)
        name.lineBreakMode = .byTruncatingTail
        addSubview(badge)
        addSubview(name)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func show(name: String, badge text: String, token: ColorToken, match: [Range<String.Index>], theme: ThemeEnvironment) {
        badgeText = text
        self.token = token
        syncHover()
        shown = (name, match)
        renderName()
        badge.setAccessibilityLabel(text)
        paint(theme)
        needsLayout = true
    }

    private static let leftAligned: NSParagraphStyle = {
        let style = NSMutableParagraphStyle()
        style.alignment = .left
        style.lineBreakMode = .byTruncatingTail
        return style
    }()

    private var shown: (String, [Range<String.Index>]) = ("", [])
    override var backgroundStyle: NSView.BackgroundStyle { didSet { renderName(); renderBadge() } }
    private func renderName() { name.attributedStringValue = highlighted(shown.0, shown.1, color: .labelColor, style: backgroundStyle) }

    func paint(_ theme: ThemeEnvironment) {
        badgeColor = theme.color(token)
        renderBadge()
    }

    /// The badge colour, or the selected-text colour on an emphasized selection (design-system §6 Sidebar rows).
    private func renderBadge() {
        let color = backgroundStyle == .emphasized ? NSColor.alternateSelectedControlTextColor : badgeColor
        badge.attributedStringValue = NSAttributedString(string: badgeText, attributes: [
            .paragraphStyle: Self.leftAligned,
            .font: NSFont.monospacedSystemFont(ofSize: 9.5, weight: .bold),
            .foregroundColor: color,
            .kern: 0.19,
        ])
        badge.textColor = color
    }

    override func layout() {
        super.layout()
        let badgeHeight = badge.cell?.cellSize.height ?? 12
        // The label keeps 2 pt of padding each side, so its frame starts 2 pt left of the cell's leading edge and the
        // left-aligned text starts on it, where a Folder's glyph would. The name follows the badge's own width, capped
        // at 56 pt (PROPFIND is 48.5), so a short method does not leave a gap before the name.
        let badgeWidth = min(badge.cell?.cellSize.width ?? 56, 56)
        badge.frame = NSRect(x: -2, y: ((bounds.height - badgeHeight) / 2).rounded(), width: badgeWidth, height: badgeHeight)
        let height = name.cell?.cellSize.height ?? 16
        name.frame = NSRect(x: badgeWidth, y: ((bounds.height - height) / 2).rounded(), width: max(0, bounds.width - badgeWidth - moreReserve), height: height)
        tipIfCut(name)
    }
}

/// A file that did not decode: the warning glyph, the file name, an icon-only Reveal in Finder
/// button, and the reason on its own line beneath.
final class UnreadableCell: MoreActionsCell, ThemedRow {
    static let identifier = NSUserInterfaceItemIdentifier("unreadable")
    let glyph = NSImageView()
    let name = NSTextField(labelWithString: "")
    let reveal: NSButton
    let reason = NSTextField(wrappingLabelWithString: "")

    private static let nameX: CGFloat = 20
    private static let reasonFont = NSFont.systemFont(ofSize: 11)

    init(target: AnyObject, action: Selector, moreAction: Selector) {
        let image = NSImage(systemSymbolName: "arrow.up.forward.square", accessibilityDescription: "Reveal in Finder")!
            .withSymbolConfiguration(.init(pointSize: 11, weight: .regular))!
        reveal = NSButton(image: image, target: target, action: action)
        super.init(target: target, action: moreAction)
        glyph.image = NSImage(systemSymbolName: "exclamationmark.triangle", accessibilityDescription: "Unreadable")?
            .withSymbolConfiguration(.init(pointSize: 12, weight: .regular))
        name.font = .systemFont(ofSize: 13)
        name.textColor = .secondaryLabelColor
        name.lineBreakMode = .byTruncatingTail
        reveal.bezelStyle = .accessoryBarAction
        reveal.toolTip = "Reveal in Finder"
        reveal.setAccessibilityLabel("Reveal in Finder")
        reason.font = Self.reasonFont
        reason.textColor = .secondaryLabelColor
        for view in [glyph, name, reveal, reason] as [NSView] { addSubview(view) }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func show(name: String, reason: String, match: [Range<String.Index>], theme: ThemeEnvironment) {
        syncHover()
        shown = (name, match)
        renderName()
        self.name.toolTip = name
        self.reason.stringValue = reason
        paint(theme)
    }

    func paint(_ theme: ThemeEnvironment) {
        warningColor = theme.color(.warning)
        renderColors()
    }

    private var warningColor = NSColor.systemYellow
    private func renderColors() {
        let emphasized = backgroundStyle == .emphasized
        glyph.contentTintColor = emphasized ? .alternateSelectedControlTextColor : warningColor
        reason.textColor = emphasized ? .alternateSelectedControlTextColor : .secondaryLabelColor
    }

    private var shown: (String, [Range<String.Index>]) = ("", [])
    override var backgroundStyle: NSView.BackgroundStyle { didSet { renderName(); renderColors() } }
    private func renderName() { name.attributedStringValue = highlighted(shown.0, shown.1, color: .secondaryLabelColor, style: backgroundStyle) }

    /// The first 24 pt line, the reason wrapped under the name, and 4 pt below.
    static func height(reason: String, cellWidth: CGFloat) -> CGFloat {
        let field = NSTextField(wrappingLabelWithString: reason)
        field.font = reasonFont
        let width = max(1, cellWidth - nameX)
        return 24 + (field.cell?.cellSize(forBounds: NSRect(x: 0, y: 0, width: width, height: .greatestFiniteMagnitude)).height ?? 14).rounded(.up) + 4
    }

    override var isFlipped: Bool { true }

    override func layout() {
        super.layout()
        glyph.frame = NSRect(x: 0, y: 5, width: 14, height: 14)
        reveal.frame = NSRect(x: bounds.width - 20 - 2 - moreReserve, y: 3, width: 20, height: 18)
        let height = name.cell?.cellSize.height ?? 16
        name.frame = NSRect(x: Self.nameX, y: ((24 - height) / 2).rounded(), width: max(0, reveal.frame.minX - 4 - Self.nameX), height: height)
        let width = max(1, bounds.width - Self.nameX)
        let reasonHeight = (reason.cell?.cellSize(forBounds: NSRect(x: 0, y: 0, width: width, height: .greatestFiniteMagnitude)).height ?? 14).rounded(.up)
        reason.frame = NSRect(x: Self.nameX, y: 24, width: width, height: reasonHeight)
    }
}

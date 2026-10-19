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

    static func tree(_ collections: [Collection]) -> [SidebarItem] {
        func items(_ nodes: [TreeNode], in parent: String) -> [SidebarItem] {
            nodes.map { node in
                switch node {
                case .folder(let name, let children):
                    SidebarItem(kind: .folder, name: name, path: parent + "/" + name, children: items(children, in: parent + "/" + name))
                case .request(let id, let name, let method, let path):
                    SidebarItem(kind: .request(id, method: method), name: name, path: path)
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
    NSMenuItemValidation {
    let sectionLabel = NSTextField(labelWithString: "Collections")
    /// The footer's + menu (board 12).
    let addMenu = NSMenu()
    let addButton = NSButton()

    /// The name sheet in the app: title, current name, confirm button, and nil on Cancel.
    var askName: (_ title: String, _ name: String, _ button: String, _ reply: @escaping (String?) -> Void) -> Void = { _, _, _, reply in reply(nil) }
    /// An alert sheet in the app, for an operation that failed.
    var showError: (String) -> Void = { _ in }
    let outline = NSOutlineView()
    let empty = NSStackView()
    let emptyText = NSTextField(wrappingLabelWithString: "No Collections yet. Create one, or save a Draft into one with ⌘S.")
    let emptyPath = NSTextField(wrappingLabelWithString: "")

    private let window: WindowModel
    private let theme: ThemeEnvironment
    private let reveal: (String) -> Void
    private var items: [SidebarItem] = []
    private var byPath: [String: SidebarItem] = [:]
    private var laidOutWidth: CGFloat = 0

    /// `reveal` gets an absolute path; NSWorkspace's file viewer in the app.
    init(window: WindowModel, theme: ThemeEnvironment, reveal: @escaping (String) -> Void) {
        self.window = window
        self.theme = theme
        self.reveal = reveal
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 232, height: 600))

        sectionLabel.font = .systemFont(ofSize: 11, weight: .semibold)
        sectionLabel.textColor = .secondaryLabelColor

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

        addMenu.addItem(NSMenuItem(title: "New Collection", action: #selector(newCollection(_:)), keyEquivalent: ""))
        addMenu.addItem(NSMenuItem(title: "New Folder", action: #selector(newFolder(_:)), keyEquivalent: ""))
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

        for child in [sectionLabel, scroll, empty, addButton] as [NSView] {
            child.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(child)
        }
        NSLayoutConstraint.activate([
            sectionLabel.topAnchor.constraint(equalTo: view.topAnchor, constant: 16),
            sectionLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
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
        let (collections, root) = withObservationTracking { (window.index.collections, window.dataFolderRoot) } onChange: { [weak self] in
            Task { @MainActor in self?.render() }
        }
        let expanded = Set(byPath.values.filter { outline.isItemExpanded($0) }.map(\.path))
        items = SidebarItem.tree(collections)
        byPath = [:]
        func index(_ items: [SidebarItem]) { for item in items { byPath[item.path] = item; index(item.children) } }
        index(items)
        outline.reloadData()
        for path in expanded.sorted() { if let item = byPath[path] { outline.expandItem(item) } }

        emptyPath.stringValue = (root as NSString).abbreviatingWithTildeInPath
        empty.isHidden = !items.isEmpty
        outline.enclosingScrollView?.isHidden = items.isEmpty
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
        activate(row: outline.clickedRow)
    }

    /// A click: a Request opens in its Tab. Anything else only selects.
    func open(row: Int) {
        guard let item = outline.item(atRow: row) as? SidebarItem, case .request(let id, _) = item.kind else { return }
        window.openRequest(id)
    }

    /// Double-click or Return: a Request opens, an unreadable file is revealed in Finder.
    func activate(row: Int) {
        guard let item = outline.item(atRow: row) as? SidebarItem else { return }
        switch item.kind {
        case .request: open(row: row)
        case .unreadable: reveal(window.dataFolderRoot + "/" + item.path)
        case .collection, .folder: break
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
        case .request, .unreadable: String(item.path[..<(item.path.range(of: "/", options: .backwards)?.lowerBound ?? item.path.endIndex)])
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
        add("New Folder…", #selector(newFolderHere), folder(of: item))
        if case .unreadable = item.kind {} else { add("Rename…", #selector(renameItem), item) }
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
            perform({ "Couldn't rename “\(item.name)”: \($0)." }) { () throws(StoreError) in try self.window.rename(item.path, to: name) }
        }
    }

    @objc private func moveItem(_ sender: NSMenuItem) {
        guard let target = sender.representedObject as? MoveTarget else { return }
        perform({ "Couldn't move “\(target.item.name)”: \($0)." }) { () throws(StoreError) in
            try self.window.move(target.item.path, to: target.folder)
        }
    }

    @objc private func trashItem(_ sender: NSMenuItem) {
        guard let item = sender.representedObject as? SidebarItem else { return }
        perform({ "Couldn't move “\(item.name)” to the Trash: \($0)." }) { () throws(StoreError) in try self.window.trash(item.path) }
    }

    @objc private func revealItem(_ sender: NSMenuItem) {
        guard let item = sender.representedObject as? SidebarItem else { return }
        reveal(window.dataFolderRoot + "/" + item.path)
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
            let cell = reuse(NodeCell.identifier) { NodeCell() }
            cell.show(item)
            return cell
        case .request(_, let method):
            let cell = reuse(RequestCell.identifier) { RequestCell() }
            cell.show(name: item.name, method: method, theme: theme)
            return cell
        case .unreadable(let reason):
            let cell = reuse(UnreadableCell.identifier) { UnreadableCell(target: self, action: #selector(revealClicked)) }
            cell.show(name: item.name, reason: reason, theme: theme)
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
}

/// A row that takes Theme colours; repainted on every Flavor change.
private protocol ThemedRow {
    func paint(_ theme: ThemeEnvironment)
}

/// A Collection or Folder: its glyph and name in system colours.
final class NodeCell: NSTableCellView {
    static let identifier = NSUserInterfaceItemIdentifier("node")
    let glyph = NSImageView()
    let name = NSTextField(labelWithString: "")

    init() {
        super.init(frame: .zero)
        glyph.contentTintColor = .secondaryLabelColor
        name.font = .systemFont(ofSize: 13)
        name.lineBreakMode = .byTruncatingTail
        addSubview(glyph)
        addSubview(name)
        imageView = glyph
        textField = name
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func show(_ item: SidebarItem) {
        let symbol = item.kind == .collection ? "square.3.layers.3d" : "folder"
        glyph.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?.withSymbolConfiguration(.init(pointSize: 12, weight: .regular))
        name.stringValue = item.name
    }

    override func layout() {
        super.layout()
        glyph.frame = NSRect(x: 0, y: (bounds.height - 14) / 2, width: 14, height: 14)
        let height = name.cell?.cellSize.height ?? 16
        name.frame = NSRect(x: 20, y: ((bounds.height - height) / 2).rounded(), width: max(0, bounds.width - 20), height: height)
    }
}

/// A Request: the 52 pt right-aligned method badge, then the name.
final class RequestCell: NSTableCellView, ThemedRow {
    static let identifier = NSUserInterfaceItemIdentifier("request")
    let badge = NSTextField(labelWithString: "")
    let name = NSTextField(labelWithString: "")
    private var method = ""

    init() {
        super.init(frame: .zero)
        badge.alignment = .right
        badge.lineBreakMode = .byTruncatingTail
        badge.font = .monospacedSystemFont(ofSize: 9.5, weight: .bold)
        name.font = .systemFont(ofSize: 13)
        name.lineBreakMode = .byTruncatingTail
        addSubview(badge)
        addSubview(name)
        textField = name
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func show(name: String, method: String, theme: ThemeEnvironment) {
        self.method = method
        self.name.stringValue = name
        badge.setAccessibilityLabel(method)
        paint(theme)
    }

    private static let rightAligned: NSParagraphStyle = {
        let style = NSMutableParagraphStyle()
        style.alignment = .right
        style.lineBreakMode = .byTruncatingTail
        return style
    }()

    func paint(_ theme: ThemeEnvironment) {
        badge.attributedStringValue = NSAttributedString(string: method, attributes: [
            .paragraphStyle: Self.rightAligned,
            .font: NSFont.monospacedSystemFont(ofSize: 9.5, weight: .bold),
            .foregroundColor: theme.color(.method(method)),
            .kern: 0.19,
        ])
        badge.textColor = theme.color(.method(method))
    }

    override func layout() {
        super.layout()
        let badgeHeight = badge.cell?.cellSize.height ?? 12
        // The label's 2 pt padding each side sits outside the 52 pt badge: PROPFIND needs 48.5.
        badge.frame = NSRect(x: -2, y: ((bounds.height - badgeHeight) / 2).rounded(), width: 56, height: badgeHeight)
        let height = name.cell?.cellSize.height ?? 16
        name.frame = NSRect(x: 58, y: ((bounds.height - height) / 2).rounded(), width: max(0, bounds.width - 58), height: height)
    }
}

/// A file that did not decode: the warning glyph, the file name, an icon-only Reveal in Finder
/// button, and the reason on its own line beneath.
final class UnreadableCell: NSTableCellView, ThemedRow {
    static let identifier = NSUserInterfaceItemIdentifier("unreadable")
    let glyph = NSImageView()
    let name = NSTextField(labelWithString: "")
    let reveal: NSButton
    let reason = NSTextField(wrappingLabelWithString: "")

    private static let nameX: CGFloat = 20
    private static let reasonFont = NSFont.systemFont(ofSize: 11)

    init(target: AnyObject, action: Selector) {
        let image = NSImage(systemSymbolName: "arrow.up.forward.square", accessibilityDescription: "Reveal in Finder")!
            .withSymbolConfiguration(.init(pointSize: 11, weight: .regular))!
        reveal = NSButton(image: image, target: target, action: action)
        super.init(frame: .zero)
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
        textField = name
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func show(name: String, reason: String, theme: ThemeEnvironment) {
        self.name.stringValue = name
        self.name.toolTip = name
        self.reason.stringValue = reason
        paint(theme)
    }

    func paint(_ theme: ThemeEnvironment) {
        glyph.contentTintColor = theme.color(.warning)
    }

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
        reveal.frame = NSRect(x: bounds.width - 20 - 2, y: 3, width: 20, height: 18)
        let height = name.cell?.cellSize.height ?? 16
        name.frame = NSRect(x: Self.nameX, y: ((24 - height) / 2).rounded(), width: max(0, reveal.frame.minX - 4 - Self.nameX), height: height)
        let width = max(1, bounds.width - Self.nameX)
        let reasonHeight = (reason.cell?.cellSize(forBounds: NSRect(x: 0, y: 0, width: width, height: .greatestFiniteMagnitude)).height ?? 14).rounded(.up)
        reason.frame = NSRect(x: Self.nameX, y: 24, width: width, height: reasonHeight)
    }
}

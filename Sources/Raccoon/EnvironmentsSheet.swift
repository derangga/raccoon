import AppKit
import Observation
import RaccoonDomain
import Security

/// The Environments sheet (design-system §6): Globals and the Environments in a source list, the
/// selected set's Variables in a table. A native sheet, so system colours, not Theme tokens. It
/// shows what the window holds and asks the window for every change; leaving a cell writes.
final class EnvironmentsSheet: NSViewController, NSTableViewDataSource, NSTableViewDelegate, NSTextFieldDelegate {
    private enum SourceRow: Equatable {
        case globals
        case header
        case environment(String)
    }

    private enum Column {
        static let enabled = NSUserInterfaceItemIdentifier("enabled")
        static let name = NSUserInterfaceItemIdentifier("name")
        static let value = NSUserInterfaceItemIdentifier("value")
        static let secret = NSUserInterfaceItemIdentifier("secret")
        /// The value cell of a secret row: a secure field, so never reused for a plain one.
        static let secretValue = NSUserInterfaceItemIdentifier("secretValue")
    }

    private static let bullets = String(repeating: "•", count: 8)
    private static let missingText = "Not in the Keychain"

    private let window: WindowModel
    let sourceTable = NSTableView()
    let addButton = NSButton(image: NSImage(systemSymbolName: "plus", accessibilityDescription: "New Environment")!, target: nil, action: nil)
    let removeButton = NSButton(image: NSImage(systemSymbolName: "minus", accessibilityDescription: "Delete Environment")!, target: nil, action: nil)
    let nameField = NSTextField()
    /// Under the name field: a refused rename.
    let renameError = EnvironmentsSheet.errorLine()
    /// Under the row that was refused, over the one below it.
    let rowError = EnvironmentsSheet.errorLine()
    let problemLabel = NSTextField(wrappingLabelWithString: "")
    let table = VariableTableView()
    let hintLabel = NSTextField(wrappingLabelWithString: "")
    let doneButton = NSButton(title: "Done", target: nil, action: nil)
    /// Under the list, as in System Settings: a hairline across the top, then + | −.
    let listFooter = NSView()
    let footerRule = NSBox()
    let footerDivider = NSBox()

    private var rows: [SourceRow] = []
    private var brokenNames: Set<String> = []
    /// An Environment's name; nil is Globals.
    private(set) var selectedName: String?
    /// The rows on screen: what the window held for the selected set when the table last loaded.
    private var shown: [VariableEntry] = []
    /// The shown secrets the Keychain cannot give, checked when the rows load. Only that it
    /// answered is kept, never what.
    private var missing: Set<VariableName> = []
    private var isOpen = true

    /// The Variables table's colours: it is drawn as the key/value table is.
    private let theme: ThemeEnvironment
    /// The Variables table's rounded border, as tall as its rows until it reaches the hint.
    let tableBox = NSScrollView()
    private lazy var tableHeight = tableBox.heightAnchor.constraint(equalToConstant: 0)

    init(window: WindowModel, theme: ThemeEnvironment) {
        self.window = window
        self.theme = theme
        super.init(nibName: nil, bundle: nil)
        title = "Environments"
        selectedName = window.activeEnvironment
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// Shown as a sheet on `window`; the field focused before is focused again when it closes.
    static func present(on parent: NSWindow, model: WindowModel, theme: ThemeEnvironment) {
        guard parent.attachedSheet == nil else { return }
        let sheet = EnvironmentsSheet(window: model, theme: theme)
        let restore = rememberFocus(in: parent)
        parent.beginSheet(sheetPanel(sheet, focus: sheet.sourceTable)) { _ in restore() }
    }

    /// surfaces.md §8: where focus returns to. A text field being edited is its field editor
    /// that has focus; the field is what gets it back.
    static func rememberFocus(in window: NSWindow) -> () -> Void {
        let previous = window.firstResponder
        let target = (previous as? NSTextView).flatMap { $0.isFieldEditor ? $0.delegate as? NSResponder : nil } ?? previous
        return { [weak window] in
            if let target { window?.makeFirstResponder(target) }
        }
    }

    // MARK: Layout

    override func loadView() {
        let root = NSView()
        root.widthAnchor.constraint(equalToConstant: 680).isActive = true
        root.heightAnchor.constraint(equalToConstant: 430).isActive = true

        let left = NSVisualEffectView()
        left.material = .sidebar
        left.blendingMode = .behindWindow
        let separators = (0..<2).map { _ in NSBox() }
        separators.forEach { $0.boxType = .separator }

        sourceTable.addTableColumn(NSTableColumn(identifier: .init("source")))
        sourceTable.headerView = nil
        sourceTable.style = .sourceList
        sourceTable.rowHeight = 24
        sourceTable.backgroundColor = .clear
        sourceTable.dataSource = self
        sourceTable.delegate = self
        sourceTable.setAccessibilityLabel("Environments")
        let sourceScroll = EnvironmentsSheet.scroll(sourceTable)
        sourceScroll.drawsBackground = false

        for (button, action) in [(addButton, #selector(add)), (removeButton, #selector(remove))] {
            button.isBordered = false
            // One size for both: sized to its own image, − was a 4 pt sliver beside +.
            button.symbolConfiguration = .init(pointSize: 13, weight: .medium)
            button.imageScaling = .scaleNone
            button.heightAnchor.constraint(equalToConstant: 22).isActive = true
            button.target = self
            button.action = action
            button.setAccessibilityLabel(button === addButton ? "New Environment" : "Delete Environment")
        }

        // Taller than its text, so the editing ring does not touch the letters.
        nameField.cell = TitleFieldCell(textCell: "")
        nameField.cell?.isScrollable = true
        nameField.cell?.usesSingleLineMode = true
        nameField.font = .systemFont(ofSize: 13, weight: .semibold)
        nameField.isBordered = false
        nameField.drawsBackground = false
        nameField.delegate = self
        nameField.setAccessibilityLabel("Environment name")

        // Drawn as the key/value table is (design-system §6 Environments sheet).
        let columns: [(NSUserInterfaceItemIdentifier, String, CGFloat)] = [(Column.enabled, "", 30), (Column.name, "Name", 150), (Column.value, "Value", 200), (Column.secret, "Secret", 48)]
        for (id, title, width) in columns {
            let column = NSTableColumn(identifier: id)
            column.headerCell = KeyHeaderCell(theme: theme, ruleBefore: id == Column.value)
            column.title = title
            column.width = width
            column.minWidth = width
            column.resizingMask = id == Column.value ? .autoresizingMask : []
            table.addTableColumn(column)
        }
        table.headerView = NSTableHeaderView(frame: NSRect(x: 0, y: 0, width: 0, height: 24))
        table.cornerView = nil
        table.style = .plain
        table.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
        table.allowsColumnReordering = false
        table.rowHeight = 28
        table.intercellSpacing = .zero
        table.gridStyleMask = .solidHorizontalGridLineMask
        table.focusRingType = .none
        table.dataSource = self
        table.delegate = self
        table.onDelete = { [unowned self] in deleteVariable(at: $0) }

        table.setAccessibilityLabel("Variables")
        tableBox.documentView = table
        tableBox.hasVerticalScroller = true
        tableBox.autohidesScrollers = true
        tableBox.scrollerStyle = .overlay
        tableBox.drawsBackground = false
        tableBox.borderType = .noBorder
        tableBox.wantsLayer = true
        tableBox.layer?.cornerRadius = 6
        tableBox.layer?.borderWidth = 1
        tableBox.layer?.masksToBounds = true
        // Cells and row views are made in each reload, so a reload recolours them.
        theme.paint(self) { sheet, theme in
            sheet.tableBox.layer?.borderColor = theme.color(.border).cgColor
            sheet.table.gridColor = theme.color(.border)
            sheet.table.backgroundColor = theme.color(.background)
            sheet.table.headerView?.needsDisplay = true
            sheet.table.reloadData()
        }
        let tableScroll = tableBox

        problemLabel.textColor = .secondaryLabelColor
        problemLabel.font = .systemFont(ofSize: 12)
        hintLabel.textColor = .secondaryLabelColor
        hintLabel.font = .systemFont(ofSize: 11)
        rowError.isHidden = true
        rowError.drawsBackground = true
        rowError.backgroundColor = .windowBackgroundColor
        renameError.isHidden = true

        doneButton.keyEquivalent = "\r"
        doneButton.target = self
        doneButton.action = #selector(done)

        footerRule.boxType = .separator
        footerDivider.boxType = .separator

        let right = NSView()
        let views: [NSView] = [left, right, sourceScroll, listFooter, footerRule, footerDivider, addButton, removeButton, nameField, renameError, tableScroll, problemLabel, hintLabel, doneButton] + separators
        for view in views { view.translatesAutoresizingMaskIntoConstraints = false }
        root.addSubview(left)
        root.addSubview(right)
        root.addSubview(separators[1])
        root.addSubview(doneButton)
        left.addSubview(sourceScroll)
        left.addSubview(listFooter)
        for view in [footerRule, addButton, footerDivider, removeButton] { listFooter.addSubview(view) }
        root.addSubview(separators[0])
        for view in [nameField, renameError, tableScroll, problemLabel, hintLabel] { right.addSubview(view) }
        // The tables' rows are Auto Layout views of their own; only the table itself is sized by hand.
        NSLayoutConstraint.activate([
            left.topAnchor.constraint(equalTo: root.topAnchor),
            left.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            left.widthAnchor.constraint(equalToConstant: 170),
            left.bottomAnchor.constraint(equalTo: separators[1].topAnchor),
            separators[0].topAnchor.constraint(equalTo: root.topAnchor),
            separators[0].leadingAnchor.constraint(equalTo: left.trailingAnchor),
            separators[0].widthAnchor.constraint(equalToConstant: 1),
            separators[0].bottomAnchor.constraint(equalTo: separators[1].topAnchor),
            right.topAnchor.constraint(equalTo: root.topAnchor),
            right.leadingAnchor.constraint(equalTo: separators[0].trailingAnchor),
            right.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            right.bottomAnchor.constraint(equalTo: separators[1].topAnchor),
            separators[1].leadingAnchor.constraint(equalTo: root.leadingAnchor),
            separators[1].trailingAnchor.constraint(equalTo: root.trailingAnchor),
            separators[1].heightAnchor.constraint(equalToConstant: 1),
            separators[1].bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -48),
            doneButton.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -16),
            doneButton.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -12),

            sourceScroll.topAnchor.constraint(equalTo: left.topAnchor, constant: 10),
            sourceScroll.leadingAnchor.constraint(equalTo: left.leadingAnchor),
            sourceScroll.trailingAnchor.constraint(equalTo: left.trailingAnchor),
            sourceScroll.bottomAnchor.constraint(equalTo: listFooter.topAnchor),
            // The list's footer, as in System Settings: a hairline, then + | −.
            listFooter.leadingAnchor.constraint(equalTo: left.leadingAnchor),
            listFooter.trailingAnchor.constraint(equalTo: left.trailingAnchor),
            listFooter.bottomAnchor.constraint(equalTo: left.bottomAnchor),
            listFooter.heightAnchor.constraint(equalToConstant: 28),
            footerRule.topAnchor.constraint(equalTo: listFooter.topAnchor),
            footerRule.leadingAnchor.constraint(equalTo: listFooter.leadingAnchor),
            footerRule.trailingAnchor.constraint(equalTo: listFooter.trailingAnchor),
            footerRule.heightAnchor.constraint(equalToConstant: 1),
            addButton.leadingAnchor.constraint(equalTo: listFooter.leadingAnchor, constant: 6),
            addButton.centerYAnchor.constraint(equalTo: listFooter.centerYAnchor),
            addButton.widthAnchor.constraint(equalToConstant: 24),
            footerDivider.leadingAnchor.constraint(equalTo: addButton.trailingAnchor, constant: 2),
            footerDivider.centerYAnchor.constraint(equalTo: listFooter.centerYAnchor),
            footerDivider.widthAnchor.constraint(equalToConstant: 1),
            footerDivider.heightAnchor.constraint(equalToConstant: 16),
            removeButton.leadingAnchor.constraint(equalTo: footerDivider.trailingAnchor, constant: 2),
            removeButton.centerYAnchor.constraint(equalTo: listFooter.centerYAnchor),
            removeButton.widthAnchor.constraint(equalToConstant: 24),

            nameField.topAnchor.constraint(equalTo: right.topAnchor, constant: 11),
            nameField.heightAnchor.constraint(equalToConstant: 24),
            nameField.leadingAnchor.constraint(equalTo: right.leadingAnchor, constant: 16),
            nameField.trailingAnchor.constraint(equalTo: right.trailingAnchor, constant: -16),
            renameError.topAnchor.constraint(equalTo: nameField.bottomAnchor, constant: 2),
            renameError.leadingAnchor.constraint(equalTo: nameField.leadingAnchor, constant: 4),
            renameError.trailingAnchor.constraint(equalTo: nameField.trailingAnchor),
            tableScroll.topAnchor.constraint(equalTo: nameField.bottomAnchor, constant: 18),
            tableScroll.leadingAnchor.constraint(equalTo: nameField.leadingAnchor),
            tableScroll.trailingAnchor.constraint(equalTo: nameField.trailingAnchor),
            tableScroll.bottomAnchor.constraint(lessThanOrEqualTo: hintLabel.topAnchor, constant: -10),
            problemLabel.topAnchor.constraint(equalTo: tableScroll.topAnchor),
            problemLabel.leadingAnchor.constraint(equalTo: nameField.leadingAnchor, constant: 4),
            problemLabel.trailingAnchor.constraint(equalTo: nameField.trailingAnchor),
            hintLabel.leadingAnchor.constraint(equalTo: nameField.leadingAnchor, constant: 4),
            hintLabel.trailingAnchor.constraint(equalTo: nameField.trailingAnchor),
            hintLabel.bottomAnchor.constraint(equalTo: right.bottomAnchor, constant: -10),
        ])
        tableHeight.priority = .defaultHigh
        tableHeight.isActive = true
        view = root
        table.addSubview(rowError)
        refresh()
        observe()
    }

    /// The border hugs the header and rows; past the hint the rows scroll inside it.
    private func fitTable() {
        let height = (table.headerView?.frame.height ?? 0) + CGFloat(table.numberOfRows) * table.rowHeight
        if tableHeight.constant != height { tableHeight.constant = height }
    }

    private static func scroll(_ table: NSTableView) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        return scroll
    }

    private static func errorLine() -> NSTextField {
        let line = NSTextField(labelWithString: "")
        line.font = .systemFont(ofSize: 11)
        line.textColor = .systemRed
        line.lineBreakMode = .byTruncatingTail
        return line
    }

    // MARK: Following the window

    private func observe() {
        withObservationTracking {
            _ = (window.environments, window.brokenEnvironments, window.globals, window.globalsProblem, window.activeEnvironment)
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self, self.isOpen else { return }
                self.refresh()
                self.observe()
            }
        }
    }

    /// The list and the detail, from the window. A table already showing what the window holds
    /// is left alone, so a cell being edited keeps its editor.
    private func refresh() {
        let broken = Dictionary(uniqueKeysWithValues: window.brokenEnvironments.map { ($0.name, $0.reason) })
        let names = (window.environments.map(\.name) + broken.keys).sorted { $0.localizedStandardCompare($1) == .orderedAscending }
        let rows: [SourceRow] = [.globals, .header] + names.map(SourceRow.environment)
        brokenNames = Set(broken.keys)
        if let selectedName, !names.contains(selectedName) { self.selectedName = nil }
        let listChanged = rows != self.rows || sourceTable.numberOfRows != rows.count
        self.rows = rows
        if listChanged { sourceTable.reloadData() } else { sourceTable.reloadData(forRowIndexes: IndexSet(rows.indices), columnIndexes: [0]) }
        selectSource()
        showSelected()
    }

    private func selectSource() {
        let row = rows.firstIndex(of: selectedName.map(SourceRow.environment) ?? .globals) ?? 0
        if sourceTable.selectedRow != row { sourceTable.selectRowIndexes([row], byExtendingSelection: false) }
    }

    private var problem: String? {
        selectedName.map { name in window.brokenEnvironments.first { $0.name == name }?.reason } ?? window.globalsProblem
    }

    private func showSelected() {
        let problem = problem
        let isEnvironment = selectedName != nil
        removeButton.isEnabled = isEnvironment
        nameField.isEditable = isEnvironment && problem == nil
        nameField.isSelectable = nameField.isEditable
        if nameField.currentEditor() == nil { nameField.stringValue = selectedName ?? "Globals" }
        let entries = window.entries(of: selectedName)
        table.enclosingScrollView?.isHidden = entries == nil
        problemLabel.isHidden = problem == nil
        problemLabel.stringValue = problem.map { "\($0). Raccoon won't change this file." } ?? ""
        hintLabel.isHidden = entries == nil
        hintLabel.stringValue = "\(selectedName.map { "\($0) overrides Globals while it is the Active Environment." } ?? "Globals apply whichever Environment is active.") Secret values are kept in the Keychain; only their names are written to the Data Folder."
        if let entries, entries != shown || table.numberOfRows != entries.count + 1 {
            shown = entries
            missing = window.missingSecrets(in: selectedName)
            table.reloadData()
            clearRowError()
        } else if entries == nil {
            shown = []
            missing = []
            table.reloadData()
        }
        fitTable()
    }

    // MARK: Test surface

    var sourceTitles: [String] {
        rows.map {
            switch $0 {
            case .globals: "Globals"
            case .header: "Environments"
            case .environment(let name): name
            }
        }
    }

    /// The source row marked as the Active Environment.
    var activeRow: Int? { window.activeEnvironment.flatMap { name in rows.firstIndex(of: .environment(name)) } }
    var brokenRows: [Int] { rows.indices.filter { if case .environment(let name) = rows[$0] { brokenNames.contains(name) } else { false } } }

    /// "Secret" or "Plain", the lock on a row's Secret column; nil on the trailing row.
    func lockName(row: Int) -> String? {
        guard let cell = table.view(atColumn: 3, row: row, makeIfNecessary: true) as? LockCell, !cell.isHidden else { return nil }
        return cell.pill.button.state == .on ? "Secret" : "Plain"
    }

    func lock(row: Int) -> NSButton? {
        (table.view(atColumn: 3, row: row, makeIfNecessary: true) as? LockCell)?.pill.button
    }

    /// What a value cell shows: its text, or for a secret the bullets or "Not in the Keychain"
    /// it is a placeholder for.
    func valueShown(row: Int) -> String? {
        guard let field = (table.view(atColumn: 2, row: row, makeIfNecessary: true) as? NSTableCellView)?.textField else { return nil }
        return field.stringValue.isEmpty ? field.placeholderAttributedString?.string ?? field.placeholderString : field.stringValue
    }

    // MARK: Data sources

    func numberOfRows(in tableView: NSTableView) -> Int {
        tableView === sourceTable ? rows.count : shown.count + 1
    }

    func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool {
        tableView !== sourceTable || rows[row] != .header
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        guard notification.object as? NSTableView === sourceTable, sourceTable.selectedRow >= 0 else { return }
        let name: String? = if case .environment(let name) = rows[sourceTable.selectedRow] { name } else { nil }
        guard name != selectedName else { return }
        selectedName = name
        renameError.stringValue = ""
        renameError.isHidden = true
        showSelected()
    }

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        guard tableView === table else { return nil }
        return KeyRowView(hover: theme.color(.rowHover), selection: theme.color(.selection), rule: theme.color(.border)) { [weak self] in
            self?.table.rect(ofColumn: 2).minX ?? 0
        }
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        if tableView === sourceTable { return sourceView(row: row) }
        guard let id = tableColumn?.identifier else { return nil }
        let isSecretValue = id == Column.value && shown.indices.contains(row) && shown[row].value == .secret
        let cellID = isSecretValue ? Column.secretValue : id
        let view = tableView.makeView(withIdentifier: cellID, owner: self) ?? makeCell(cellID)
        fill(view, id, row: row)
        return view
    }

    private func sourceView(row: Int) -> NSView {
        let cell = NSTableCellView()
        let label = NSTextField(labelWithString: "")
        label.translatesAutoresizingMaskIntoConstraints = false
        label.lineBreakMode = .byTruncatingTail
        cell.addSubview(label)
        cell.textField = label
        var trailing: NSImageView?
        switch rows[row] {
        case .globals:
            label.stringValue = "Globals"
            if window.globalsProblem != nil { trailing = EnvironmentsSheet.badge("exclamationmark.triangle.fill", "Can't be read", .systemOrange) }
        case .header:
            label.stringValue = "Environments"
            label.font = .systemFont(ofSize: 11, weight: .semibold)
            label.textColor = .secondaryLabelColor
        case .environment(let name):
            label.stringValue = name
            if brokenNames.contains(name) {
                trailing = EnvironmentsSheet.badge("exclamationmark.triangle.fill", "Can't be read", .systemOrange)
            } else if name == window.activeEnvironment {
                trailing = EnvironmentsSheet.badge("checkmark", "Active Environment", .secondaryLabelColor)
            }
        }
        label.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 4).isActive = true
        label.centerYAnchor.constraint(equalTo: cell.centerYAnchor).isActive = true
        if let trailing {
            trailing.translatesAutoresizingMaskIntoConstraints = false
            cell.addSubview(trailing)
            NSLayoutConstraint.activate([
                trailing.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -6),
                trailing.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                label.trailingAnchor.constraint(equalTo: trailing.leadingAnchor, constant: -4),
            ])
        } else {
            label.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -4).isActive = true
        }
        return cell
    }

    private static func badge(_ symbol: String, _ label: String, _ color: NSColor) -> NSImageView {
        let view = NSImageView(image: NSImage(systemSymbolName: symbol, accessibilityDescription: label)!)
        view.symbolConfiguration = .init(pointSize: 11, weight: .regular)
        view.contentTintColor = color
        view.toolTip = label
        return view
    }

    private func makeCell(_ id: NSUserInterfaceItemIdentifier) -> NSView {
        let view: NSView
        switch id {
        case Column.enabled:
            let box = NSButton(checkboxWithTitle: "", target: self, action: #selector(toggleEnabled))
            box.bezelColor = theme.color(.accent)
            box.setAccessibilityLabel("Enabled")
            view = box
        case Column.secret:
            let cell = LockCell()
            cell.pill.button.target = self
            cell.pill.button.action = #selector(toggleSecret)
            view = cell
        default:
            let field = id == Column.secretValue ? NSSecureTextField() : NSTextField()
            field.isBordered = false
            field.drawsBackground = false
            field.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
            field.lineBreakMode = .byTruncatingTail
            field.cell?.usesSingleLineMode = true
            field.delegate = self
            // In the middle of the row like the checkbox and the lock beside it; edited, the whole cell.
            view = EditableCellView(field: field, inset: 4, ring: theme.color(.focusRing), fill: theme.color(.background))
        }
        view.identifier = id
        return view
    }

    /// One cell from the model. A field already showing its text is left alone, so an open editor
    /// keeps its caret.
    private func fill(_ view: NSView, _ id: NSUserInterfaceItemIdentifier, row: Int) {
        if let cell = view as? EditableCellView {
            // A reused cell may predate a Flavor change.
            cell.ring = theme.color(.focusRing)
            cell.fill = theme.color(.background)
        }
        let view = (view as? NSTableCellView)?.textField ?? view
        let entry = shown.indices.contains(row) ? shown[row] : nil
        let dimmed = entry?.isEnabled == false
        let ink = theme.color(dimmed ? .textDisabled : .text)
        func set(_ field: NSTextField, _ text: String) { if field.stringValue != text { field.stringValue = text } }
        /// The trailing row's "Name" / "Value", as in the key/value table: SF Pro 13, `textTertiary` at 60 %.
        func placeholder(_ text: String) -> NSAttributedString {
            NSAttributedString(string: text, attributes: [.font: NSFont.systemFont(ofSize: 13), .foregroundColor: theme.color(.textTertiary).withAlphaComponent(0.6)])
        }
        switch (view, id) {
        case (let box as NSButton, _):
            box.state = entry?.isEnabled == true ? .on : .off
            box.isEnabled = entry != nil
            box.bezelColor = theme.color(.accent)
        case (let cell as LockCell, _):
            let on = entry?.value == .secret
            let button = cell.pill.button
            cell.isHidden = entry == nil
            cell.pill.onColor = theme.color(.selection)
            cell.pill.isOn = on
            button.state = on ? .on : .off
            button.image = NSImage(systemSymbolName: on ? "lock" : "lock.open", accessibilityDescription: nil)
            button.contentTintColor = theme.color(on ? .text : .textTertiary)
            button.setAccessibilityLabel(on ? "Secret, click to make plain" : "Make secret")
        case (let field as NSTextField, Column.name):
            set(field, entry?.name.rawValue ?? "")
            field.placeholderAttributedString = placeholder("Name")
            field.textColor = ink
        case (let field as NSTextField, _):
            field.placeholderAttributedString = placeholder("Value")
            field.textColor = ink
            switch entry?.value {
            case .plain(let text)?:
                set(field, text)
                field.isEditable = true
            case .secret?:
                // The field is empty and the bullets are its placeholder, so typing replaces the
                // value and neither the value nor its length is ever drawn.
                set(field, "")
                let isMissing = entry.map { missing.contains($0.name) } ?? false
                field.placeholderAttributedString = NSAttributedString(string: isMissing ? Self.missingText : Self.bullets, attributes: [
                    .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular),
                    .foregroundColor: theme.color(isMissing ? .textTertiary : dimmed ? .textDisabled : .text),
                ])
                field.isEditable = true
            case nil:
                set(field, "")
                field.isEditable = true
            }
        default: break
        }
    }

    /// Every cell of a row, in place: a view being edited is not replaced.
    private func reloadRow(_ row: Int) {
        for (index, column) in table.tableColumns.enumerated() {
            if let view = table.view(atColumn: index, row: row, makeIfNecessary: false) { fill(view, column.identifier, row: row) }
        }
    }

    // MARK: Editing

    func controlTextDidBeginEditing(_ notification: Notification) {
        clearRowError()
        renameError.isHidden = true
    }

    func controlTextDidEndEditing(_ notification: Notification) {
        guard let field = notification.object as? NSTextField else { return }
        if field === nameField { return commitName() }
        let row = table.row(for: field), column = table.column(for: field)
        guard row >= 0, column >= 0 else { return }
        commit(field.stringValue, row: row, column: table.tableColumns[column].identifier)
    }

    private func commit(_ text: String, row: Int, column: NSUserInterfaceItemIdentifier) {
        var entries = shown
        let isNew = row == entries.count
        if column == Column.name {
            let trimmed = text.trimmingCharacters(in: .whitespaces)
            if isNew ? trimmed.isEmpty : trimmed == entries[row].name.rawValue { return reloadRow(row) }
            do throws(VariableEdit.Refusal) {
                let name = try VariableEdit.name(text, in: entries, replacing: isNew ? nil : row)
                if isNew { entries.append(VariableEntry(name: name, value: .plain(""))) } else { entries[row].name = name }
            } catch {
                showRowError(error.message(in: selectedName), row: row)
                return reloadRow(row)
            }
        } else {
            // A value typed with no name beside it goes nowhere.
            guard !isNew else { return reloadRow(row) }
            switch entries[row].value {
            case .secret: return commitSecret(text, row: row)
            case .plain(let old):
                guard text != old else { return reloadRow(row) }
                entries[row].value = .plain(text)
            }
        }
        save(entries, row: row)
    }

    /// Typing in a secret's field replaces its value in the Keychain; the file holds none. Nothing
    /// typed leaves it as it was.
    private func commitSecret(_ text: String, row: Int) {
        guard !text.isEmpty else { return reloadRow(row) }
        do throws(SecretError) {
            try window.setSecretValue(text, at: row, in: selectedName)
            missing.remove(shown[row].name)
        } catch {
            showRowError(Self.message(error), row: row)
        }
        reloadRow(row)
    }

    /// The lock: marks a plain row, unmarks a secret one. A refusal leaves the row as it was.
    @objc func toggleSecret(_ sender: NSButton) {
        endEditing()
        let row = table.row(for: sender)
        guard shown.indices.contains(row) else { return }
        clearRowError()
        let entry = shown[row]
        do throws(SecretEditError) {
            if entry.value == .secret {
                do throws(StoreError) { try window.unmarkSecret(at: row, in: selectedName) } catch { throw .store(error) }
            } else {
                try window.markSecret(at: row, in: selectedName)
            }
        } catch {
            switch error {
            case .store(let error): showRowError("Not saved. \(Self.sentence(Self.reason(error)))", row: row)
            case .secret(let error): showRowError(Self.message(error), row: row)
            }
            return reloadRow(row)
        }
        shown = window.entries(of: selectedName) ?? shown
        // A plain row marked with no value has nothing in the Keychain yet.
        missing.remove(entry.name)
        if entry.value == .plain("") { missing.insert(entry.name) }
        // The value cell changes kind, so the row's views are replaced.
        table.reloadData(forRowIndexes: [row], columnIndexes: IndexSet(table.tableColumns.indices))
    }

    @objc func toggleEnabled(_ sender: NSButton) {
        let row = table.row(for: sender)
        guard shown.indices.contains(row) else { return }
        var entries = shown
        entries[row].isEnabled = sender.state == .on
        save(entries, row: row)
    }

    private func save(_ entries: [VariableEntry], row: Int) {
        clearRowError()
        do throws(StoreError) {
            try window.write(entries, to: selectedName)
        } catch {
            showRowError("Not saved. \(Self.sentence(Self.reason(error)))", row: row)
            return reloadRow(row)
        }
        let grew = entries.count > shown.count
        shown = entries
        // The data source answers first, then the table is told.
        if grew { table.insertRows(at: [entries.count], withAnimation: []); fitTable() }
        reloadRow(row)
    }

    func deleteVariable(at row: Int) {
        guard shown.indices.contains(row) else { return }
        clearRowError()
        do throws(StoreError) {
            try window.removeVariable(at: row, from: selectedName)
        } catch {
            return showRowError("Not saved. \(Self.sentence(Self.reason(error)))", row: row)
        }
        shown.remove(at: row)
        table.removeRows(at: [row], withAnimation: [])
        fitTable()
    }

    private func showRowError(_ text: String, row: Int) {
        rowError.stringValue = text
        rowError.isHidden = false
        let below = table.rect(ofRow: row)
        let x = table.rect(ofColumn: 1).minX + 6
        rowError.frame = NSRect(x: x, y: below.maxY - 3, width: max(table.bounds.width - x - 8, 100), height: 16)
        table.scrollToVisible(rowError.frame)
    }

    private func clearRowError() {
        rowError.stringValue = ""
        rowError.isHidden = true
    }

    private func commitName() {
        guard let old = selectedName, nameField.isEditable else { return }
        do throws(EnvironmentEditError) {
            let new = try window.renameEnvironment(old, to: nameField.stringValue)
            selectedName = new
            nameField.stringValue = new
            showRenameError(nil)
            refresh()
        } catch {
            nameField.stringValue = old
            switch error {
            case .empty: showRenameError(nil)
            case .nameTaken(let taken): showRenameError("An Environment named “\(taken)” already exists.")
            case .store(let error): showRenameError("Not saved. \(Self.sentence(Self.reason(error)))")
            case .secret(.unavailable(let status)): showRenameError("Not saved. The Keychain refused the request (OSStatus \(status)).")
            case .secret(.raccoonJSONUnreadable): showRenameError("Not saved. raccoon.json can't be read.")
            }
        }
    }

    private func showRenameError(_ text: String?) {
        renameError.stringValue = text ?? ""
        renameError.isHidden = text == nil
    }

    static func reason(_ error: StoreError) -> String {
        switch error {
        case .unreadable(_, let reason), .undecodable(_, let reason), .unwritable(_, let reason): reason
        }
    }

    /// The line under a row whose secret the Keychain refused (design-system §6).
    static func message(_ error: SecretError) -> String {
        switch error {
        case .unavailable(let status):
            var text = (SecCopyErrorMessageString(status, nil) as String?) ?? ""
            if text.hasSuffix(".") { text.removeLast() }
            let number = String(status).replacingOccurrences(of: "-", with: "−")
            return "Not saved. The Keychain refused the write (OSStatus \(number)\(text.isEmpty ? "" : ", " + text))."
        case .raccoonJSONUnreadable: return "Not saved. raccoon.json can't be read."
        }
    }

    static func sentence(_ reason: String) -> String {
        let capital = reason.prefix(1).uppercased() + reason.dropFirst()
        return capital.hasSuffix(".") ? capital : capital + "."
    }

    // MARK: + − Done

    @objc private func add() {
        endEditing()
        do throws(StoreError) {
            selectedName = try window.newEnvironment()
        } catch {
            return showRenameError("Not saved. \(Self.sentence(Self.reason(error)))")
        }
        showRenameError(nil)
        refresh()
        view.window?.makeFirstResponder(nameField)
        nameField.currentEditor()?.selectAll(nil)
    }

    @objc private func remove() {
        guard let name = selectedName else { return }
        endEditing()
        do throws(StoreError) {
            try window.deleteEnvironment(name)
        } catch {
            return showRenameError("Not saved. \(Self.sentence(Self.reason(error)))")
        }
        selectedName = nil
        showRenameError(nil)
        refresh()
    }

    /// A button does not take focus from a field being edited, so its edit would be lost.
    private func endEditing() {
        view.window?.makeFirstResponder(nil)
    }

    @objc private func done() {
        endEditing()
        isOpen = false
        if let panel = view.window, let parent = panel.sheetParent { parent.endSheet(panel) }
    }

    /// Esc.
    override func cancelOperation(_ sender: Any?) { done() }
}

/// The lock, on an `onColor` pill while the row is secret.
final class LockPill: NSView {
    let button = NSButton()
    var isOn = false { didSet { needsDisplay = true } }
    var onColor = NSColor.unemphasizedSelectedContentBackgroundColor { didSet { needsDisplay = true } }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = 4
        button.isBordered = false
        button.imagePosition = .imageOnly
        button.setButtonType(.momentaryChange)
        button.translatesAutoresizingMaskIntoConstraints = false
        addSubview(button)
        NSLayoutConstraint.activate([
            button.leadingAnchor.constraint(equalTo: leadingAnchor), button.trailingAnchor.constraint(equalTo: trailingAnchor),
            button.topAnchor.constraint(equalTo: topAnchor), button.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = isOn ? onColor.cgColor : nil
        }
    }
}

/// The Secret column's cell: the lock, 24 × 20, centred.
final class LockCell: NSView {
    let pill = LockPill()

    init() {
        super.init(frame: .zero)
        pill.translatesAutoresizingMaskIntoConstraints = false
        addSubview(pill)
        NSLayoutConstraint.activate([
            pill.centerXAnchor.constraint(equalTo: centerXAnchor), pill.centerYAnchor.constraint(equalTo: centerYAnchor),
            pill.widthAnchor.constraint(equalToConstant: 24), pill.heightAnchor.constraint(equalToConstant: 20),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }
}

/// The Environment's name: its text and its editor one line tall in the middle of the field, 2 pt in.
final class TitleFieldCell: NSTextFieldCell {
    override func drawingRect(forBounds rect: NSRect) -> NSRect {
        oneLine(centeredIn: super.drawingRect(forBounds: rect).insetBy(dx: 2, dy: 0))
    }

    override func edit(withFrame rect: NSRect, in controlView: NSView, editor: NSText, delegate: Any?, event: NSEvent?) {
        super.edit(withFrame: drawingRect(forBounds: rect), in: controlView, editor: editor, delegate: delegate, event: event)
    }

    override func select(withFrame rect: NSRect, in controlView: NSView, editor: NSText, delegate: Any?, start selStart: Int, length selLength: Int) {
        super.select(withFrame: drawingRect(forBounds: rect), in: controlView, editor: editor, delegate: delegate, start: selStart, length: selLength)
    }
}

/// The Variables table: ⌫ deletes the selected row, as does the row's context menu.
final class VariableTableView: NSTableView {
    var onDelete: (Int) -> Void = { _ in }

    override func keyDown(with event: NSEvent) {
        // 51 is delete, 117 forward delete.
        if event.keyCode == 51 || event.keyCode == 117, selectedRow >= 0 { return onDelete(selectedRow) }
        super.keyDown(with: event)
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let row = row(at: convert(event.locationInWindow, from: nil))
        guard row >= 0 else { return nil }
        selectRowIndexes([row], byExtendingSelection: false)
        let menu = NSMenu()
        let item = NSMenuItem(title: "Delete Variable", action: #selector(deleteSelected), keyEquivalent: "")
        item.target = self
        menu.addItem(item)
        return menu
    }

    @objc private func deleteSelected() {
        if selectedRow >= 0 { onDelete(selectedRow) }
    }
}

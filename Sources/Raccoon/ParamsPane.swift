import AppKit
import RaccoonDomain

/// The Params pane: "Query Params" over the key/value table, and while the URL has a Path Variable
/// "Path Variables" over a second table, in one scroll view (design-system.md §6).
final class ParamsPane: NSView {
    let queryTable: KeyValueTable
    let pathTable: PathVariableTable
    let queryLabel: NSTextField
    let pathLabel: NSTextField
    let scroll = NSScrollView()
    private let stack = NSStackView()

    init(theme: ThemeEnvironment) {
        queryTable = KeyValueTable(theme: theme)
        pathTable = PathVariableTable(theme: theme)
        queryLabel = Self.label("Query Params", theme: theme)
        pathLabel = Self.label("Path Variables", theme: theme)
        super.init(frame: .zero)
        queryTable.forwardsScrolling = true

        stack.orientation = .vertical
        stack.alignment = .width
        stack.spacing = 0
        stack.setViews([queryLabel, queryTable, pathLabel, pathTable], in: .top)
        // 12 pt above the second label.
        stack.setCustomSpacing(12, after: queryTable)
        pathLabel.isHidden = true
        pathTable.isHidden = true

        let document = FlippedView()
        stack.translatesAutoresizingMaskIntoConstraints = false
        document.addSubview(stack)
        scroll.documentView = document
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.scrollerStyle = .overlay
        scroll.translatesAutoresizingMaskIntoConstraints = false
        addSubview(scroll)
        let clip = scroll.contentView
        document.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            scroll.leadingAnchor.constraint(equalTo: leadingAnchor), scroll.trailingAnchor.constraint(equalTo: trailingAnchor),
            scroll.topAnchor.constraint(equalTo: topAnchor), scroll.bottomAnchor.constraint(equalTo: bottomAnchor),
            document.topAnchor.constraint(equalTo: clip.topAnchor),
            document.leadingAnchor.constraint(equalTo: clip.leadingAnchor),
            document.trailingAnchor.constraint(equalTo: clip.trailingAnchor),
            stack.topAnchor.constraint(equalTo: document.topAnchor),
            stack.leadingAnchor.constraint(equalTo: document.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: document.trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: document.bottomAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// A 24 pt row, 12 pt SF Pro semibold `textSecondary`.
    private static func label(_ text: String, theme: ThemeEnvironment) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 12, weight: .semibold)
        theme.paint(label) { $0.textColor = $1.color(.textSecondary) }
        label.heightAnchor.constraint(equalToConstant: 24).isActive = true
        // The stack stretches a label to the pane's width; at the default hugging it keeps its text's width and sits at the trailing edge.
        label.setContentHuggingPriority(.init(1), for: .horizontal)
        label.setAccessibilityRole(.staticText)
        return label
    }

    /// The Path Variables section follows the URL: none, no label and no table.
    func setPathVariables(names: [String], values: [String: String], kinds: VariableKinds) {
        pathTable.setKinds(kinds)
        pathTable.setRows(names, values: values)
        pathLabel.isHidden = names.isEmpty
        pathTable.isHidden = names.isEmpty
    }
}

/// The Path Variables table (design-system.md §6): a read-only Name and an editable Value for each
/// `:name` in the URL. No checkbox, no delete, no trailing row, no hover fill. Rows come and go with
/// the URL, in place, so the Value cell being edited keeps its field editor.
final class PathVariableTable: NSView, NSTableViewDataSource, NSTableViewDelegate, NSTextFieldDelegate {
    /// A Value cell was edited: the name and the text as typed.
    var onChange: (String, String) -> Void = { _, _ in }
    private(set) var names: [String] = []
    private var values: [String: String] = [:]
    private var kinds: VariableKinds?
    private let theme: ThemeEnvironment
    let table = KeyTableView()
    private let scroll = ForwardingScrollView()
    private let columns = (name: NSTableColumn(identifier: .init("name")), value: NSTableColumn(identifier: .init("value")))

    init(theme: ThemeEnvironment) {
        self.theme = theme
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 6
        layer?.borderWidth = 1
        layer?.masksToBounds = true
        setAccessibilityLabel("Path Variables")

        for (column, title) in [(columns.name, "Name"), (columns.value, "Value")] {
            column.headerCell = KeyHeaderCell(theme: theme, ruleBefore: column === columns.value)
            column.title = title
            column.resizingMask = []
            table.addTableColumn(column)
        }
        table.headerView = NSTableHeaderView(frame: NSRect(x: 0, y: 0, width: 0, height: 24))
        table.cornerView = nil
        table.style = .plain
        table.rowHeight = 28
        table.intercellSpacing = .zero
        table.gridStyleMask = [.solidHorizontalGridLineMask]
        table.columnAutoresizingStyle = .noColumnAutoresizing
        table.allowsColumnReordering = false
        table.allowsColumnSelection = false
        table.focusRingType = .none
        table.dataSource = self
        table.delegate = self
        theme.paint(self) { view, theme in
            view.layer?.borderColor = theme.color(.border).cgColor
            view.table.gridColor = theme.color(.border)
            view.table.backgroundColor = theme.color(.background)
            view.table.headerView?.needsDisplay = true
            view.table.reloadData()
        }

        scroll.documentView = table
        scroll.forwards = true
        scroll.hasVerticalScroller = false
        scroll.verticalScrollElasticity = .none
        scroll.drawsBackground = false
        scroll.translatesAutoresizingMaskIntoConstraints = false
        addSubview(scroll)
        NSLayoutConstraint.activate([
            scroll.leadingAnchor.constraint(equalTo: leadingAnchor), scroll.trailingAnchor.constraint(equalTo: trailingAnchor),
            scroll.topAnchor.constraint(equalTo: topAnchor), scroll.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// As tall as its rows: the pane scrolls, the table does not.
    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: 24 + CGFloat(names.count) * table.rowHeight)
    }

    /// Name takes 36 %, Value the rest, as in the key/value table.
    override func layout() {
        super.layout()
        columns.name.width = (bounds.width * 0.36).rounded()
        columns.value.width = bounds.width - columns.name.width
    }

    /// Rows that stay keep their views: a row that leaves or arrives is removed or inserted where it
    /// is, so the cell being edited keeps its field editor. A Value that changed under a cell not being
    /// edited is written into it.
    func setRows(_ newNames: [String], values newValues: [String: String]) {
        guard newNames != names || newValues != values else { return }
        let old = names
        names = newNames
        values = newValues
        if newNames != old {
            table.beginUpdates()
            for change in newNames.difference(from: old) {
                switch change {
                case .remove(let offset, _, _): table.removeRows(at: IndexSet(integer: offset), withAnimation: [])
                case .insert(let offset, _, _): table.insertRows(at: IndexSet(integer: offset), withAnimation: [])
                }
            }
            table.endUpdates()
            invalidateIntrinsicContentSize()
        }
        table.enumerateAvailableRowViews { rowView, row in
            guard names.indices.contains(row), let field = (rowView.view(atColumn: 1) as? NSTableCellView)?.textField as? KeyField else { return }
            let value = values[names[row]] ?? ""
            guard field.currentEditor() == nil, field.stringValue != value else { return }
            field.stringValue = value
            field.toolTip = value.isEmpty ? nil : value
            field.highlight()
        }
    }

    /// Recolours the Value cells on screen in place, so a field being edited keeps its editor.
    func setKinds(_ new: VariableKinds) {
        guard new != kinds else { return }
        kinds = new
        table.enumerateAvailableRowViews { rowView, _ in
            ((rowView.view(atColumn: 1) as? NSTableCellView)?.textField as? KeyField)?.kinds = new
        }
    }

    func controlTextDidChange(_ notification: Notification) {
        guard let field = notification.object as? NSTextField else { return }
        let row = table.row(for: field)
        guard names.indices.contains(row) else { return }
        field.toolTip = field.stringValue.isEmpty ? nil : field.stringValue
        // The model hands the same value back; the cell already shows it.
        values[names[row]] = field.stringValue.isEmpty ? nil : field.stringValue
        onChange(names[row], field.stringValue)
    }

    // MARK: Data source and cells

    func numberOfRows(in tableView: NSTableView) -> Int { names.count }

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        // No hover fill and no selection: a row is not a thing to pick.
        KeyRowView(hover: .clear, selection: .clear, rule: theme.color(.border)) { [weak self] in self?.table.rect(ofColumn: 1).minX ?? 0 }
    }

    func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool { false }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let name = names[row]
        if tableColumn === columns.name { return nameCell(name) }
        let field = KeyValueTable.cellField(theme: theme)
        field.stringValue = values[name] ?? ""
        field.toolTip = field.stringValue.isEmpty ? nil : field.stringValue
        field.textColor = theme.color(.text)
        field.kinds = kinds
        field.highlight()
        field.placeholderAttributedString = NSAttributedString(string: "Value", attributes: [
            .font: NSFont.systemFont(ofSize: 13), .foregroundColor: theme.color(.textTertiary).withAlphaComponent(0.6),
        ])
        field.delegate = self
        field.setAccessibilityLabel("Value")
        return KeyValueTable.cellView(field, theme: theme)
    }

    /// SF Mono 12 `textSecondary`, the name without its `:`. A label: no field editor, so a click does nothing.
    private func nameCell(_ name: String) -> NSView {
        let label = NSTextField(labelWithString: name)
        label.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        label.textColor = theme.color(.textSecondary)
        label.lineBreakMode = .byTruncatingTail
        label.toolTip = name
        label.setAccessibilityLabel("Name")
        label.setAccessibilityValue(name)
        label.translatesAutoresizingMaskIntoConstraints = false
        let cell = NSTableCellView()
        cell.textField = label
        cell.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 8),
            label.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -8),
            label.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
        ])
        return cell
    }
}

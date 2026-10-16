import AppKit
import RaccoonDomain

/// The key/value table shared by Params, Headers, Cookies, form-urlencoded and multipart
/// (design-system.md §6). Rows come in through `setRows`; every edit goes out through
/// `onChange`, already applied, so the owner stores it and sets it back without a reload.
final class KeyValueTable: NSView, NSTableViewDataSource, NSTableViewDelegate, NSTextFieldDelegate {
    static let deleteID = NSUserInterfaceItemIdentifier("delete")
    var onChange: ([Row]) -> Void = { _ in }
    private(set) var rows: [Row] = []
    /// Headers only: what is sent that no row sets, after the trailing empty row, read-only.
    private var automatic: [AutomaticHeader] = []
    private let theme: ThemeEnvironment
    /// Multipart only: a value can be a file, drawn as a chip, picked or dropped onto a row.
    private let allowsFiles: Bool
    /// Beside `rows`, one per row: whether its value is a file path.
    private(set) var files: [Bool] = []
    /// The file a send could not read, drawn with its chip in `error`.
    var missingFile: String? {
        didSet { if missingFile != oldValue { table.reloadData() } }
    }
    let table = KeyTableView()
    private let scroll = NSScrollView()
    private let columns = (check: NSTableColumn(identifier: .init("check")), name: NSTableColumn(identifier: .init("name")),
                           value: NSTableColumn(identifier: .init("value")), delete: NSTableColumn(identifier: .init("delete")))

    init(theme: ThemeEnvironment, allowsFiles: Bool = false) {
        self.theme = theme
        self.allowsFiles = allowsFiles
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 6
        layer?.borderWidth = 1
        layer?.borderColor = theme.color(.border).cgColor
        layer?.masksToBounds = true

        for (column, title, width) in [(columns.check, "", 30.0), (columns.name, "Name", 120), (columns.value, "Value", 200), (columns.delete, "", 30)] {
            column.headerCell = HeaderCell(theme: theme)
            column.title = title
            column.width = width
            column.resizingMask = []
            table.addTableColumn(column)
        }
        table.headerView = NSTableHeaderView(frame: NSRect(x: 0, y: 0, width: 0, height: 24))
        table.cornerView = nil
        table.style = .plain
        table.rowHeight = 28
        table.intercellSpacing = .zero
        table.gridStyleMask = [.solidHorizontalGridLineMask, .solidVerticalGridLineMask]
        table.gridColor = theme.color(.border)
        table.backgroundColor = theme.color(.background)
        table.columnAutoresizingStyle = .noColumnAutoresizing
        table.allowsColumnReordering = false
        table.focusRingType = .none
        table.dataSource = self
        table.delegate = self
        table.keys = self
        if allowsFiles {
            table.registerForDraggedTypes([.fileURL])
            let menu = NSMenu()
            let choose = NSMenuItem(title: "Choose File…", action: #selector(chooseFile), keyEquivalent: "")
            choose.target = self
            menu.addItem(choose)
            table.menu = menu
        }

        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.scrollerStyle = .overlay
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

    /// Rows equal to the ones shown are ignored, so an edit echoed back keeps the field editor.
    func setRows(_ new: [Row]) {
        guard new != rows else { return }
        rows = new
        table.reloadData()
        invalidateIntrinsicContentSize()
    }

    func setParts(_ parts: [Part]) {
        let new = parts.map { part in
            switch part.content {
            case .text(let value): Row(name: part.name, value: value, isEnabled: part.isEnabled)
            case .file(let path): Row(name: part.name, value: path, isEnabled: part.isEnabled)
            }
        }
        let newFiles = parts.map { if case .file = $0.content { true } else { false } }
        guard new != rows || newFiles != files else { return }
        files = newFiles
        rows = new
        table.reloadData()
        invalidateIntrinsicContentSize()
    }

    /// `rows` as Parts, a file row's value being its path.
    func parts(_ rows: [Row]) -> [Part] {
        rows.enumerated().map { index, row in
            let isFile = files.indices.contains(index) && files[index]
            return Part(name: row.name, isEnabled: row.isEnabled, content: isFile ? .file(path: row.value) : .text(row.value))
        }
    }

    /// The trailing row becomes a new file part; any other row's value becomes the file.
    func setFile(_ path: String, at row: Int) {
        guard row <= rows.count else { return }
        if row == rows.count {
            rows.append(Row(name: "", value: path))
            files.append(true)
            table.insertRows(at: IndexSet(integer: rows.count), withAnimation: [])
            invalidateIntrinsicContentSize()
        } else {
            rows[row].value = path
            files[row] = true
        }
        onChange(rows)
        table.reloadData(forRowIndexes: IndexSet(integer: row), columnIndexes: IndexSet(integersIn: 0..<4))
    }

    @objc private func chooseFile() {
        let row = table.clickedRow >= 0 && table.clickedRow <= rows.count ? table.clickedRow : rows.count
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        guard let window else { return }
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            self?.setFile(url.path, at: row)
        }
    }

    func tableView(_ tableView: NSTableView, validateDrop info: any NSDraggingInfo, proposedRow row: Int,
                   proposedDropOperation dropOperation: NSTableView.DropOperation) -> NSDragOperation {
        guard allowsFiles, row <= rows.count else { return [] }
        tableView.setDropRow(row, dropOperation: .on)
        return .copy
    }

    func tableView(_ tableView: NSTableView, acceptDrop info: any NSDraggingInfo, row: Int, dropOperation: NSTableView.DropOperation) -> Bool {
        let urls = info.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL]
        guard let url = urls?.first else { return false }
        setFile(url.path, at: row)
        return true
    }

    /// Replaces only the automatic rows, so a field being edited above them keeps its editor.
    func setAutomaticRows(_ new: [AutomaticHeader]) {
        guard new != automatic else { return }
        let start = rows.count + 1
        table.beginUpdates()
        table.removeRows(at: IndexSet(integersIn: start..<start + automatic.count), withAnimation: [])
        automatic = new
        table.insertRows(at: IndexSet(integersIn: start..<start + automatic.count), withAnimation: [])
        table.endUpdates()
        invalidateIntrinsicContentSize()
    }

    /// As tall as its rows; the owner caps it at the pane, and past that the rows scroll.
    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: 24 + CGFloat(table.numberOfRows) * table.rowHeight + 2)
    }

    /// Name takes 36 %, Value the rest (design-system.md §6).
    override func layout() {
        super.layout()
        let flexible = max(0, bounds.width - 60)
        columns.name.width = (flexible * 0.36).rounded()
        columns.value.width = flexible - columns.name.width
    }

    // MARK: Edits

    private func apply(_ new: [Row]) {
        let added = new.count - rows.count
        rows = new
        if added > 0 { files += Array(repeating: false, count: added) }
        if added > 0 {
            table.insertRows(at: IndexSet(integer: rows.count), withAnimation: [])
            invalidateIntrinsicContentSize()
        }
        onChange(rows)
    }

    func toggle(row: Int) {
        guard rows.indices.contains(row) else { return }
        apply(Rows.toggle(at: row, in: rows))
        table.reloadData(forRowIndexes: IndexSet(integer: row), columnIndexes: IndexSet(integersIn: 0..<4))
    }

    func delete(row: Int) {
        guard rows.indices.contains(row) else { return }
        rows = Rows.delete(at: row, in: rows)
        if files.indices.contains(row) { files.remove(at: row) }
        table.removeRows(at: IndexSet(integer: row), withAnimation: [])
        invalidateIntrinsicContentSize()
        onChange(rows)
    }

    @objc private func checkboxClicked(_ sender: NSButton) { toggle(row: table.row(for: sender)) }
    @objc private func deleteClicked(_ sender: NSButton) { delete(row: table.row(for: sender)) }

    func controlTextDidChange(_ notification: Notification) {
        guard let field = notification.object as? NSTextField else { return }
        let row = table.row(for: field)
        guard row >= 0 else { return }
        let wasTrailing = row == rows.count
        apply(field.tag == 0 ? Rows.setName(field.stringValue, at: row, in: rows) : Rows.setValue(field.stringValue, at: row, in: rows))
        field.toolTip = field.stringValue
        // The trailing row became a real row: give it its checkbox and its delete button.
        if wasTrailing { table.reloadData(forRowIndexes: IndexSet(integer: row), columnIndexes: [0, 3]) }
    }

    func controlTextDidBeginEditing(_ notification: Notification) {
        guard let field = notification.object as? NSTextField else { return }
        field.layer?.borderWidth = 2
        field.layer?.backgroundColor = theme.color(.background).cgColor
    }

    func controlTextDidEndEditing(_ notification: Notification) {
        guard let field = notification.object as? NSTextField else { return }
        field.layer?.borderWidth = 0
        field.layer?.backgroundColor = nil
    }

    // MARK: Data source and cells

    func numberOfRows(in tableView: NSTableView) -> Int { rows.count + 1 + automatic.count }

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        HoverRowView(hover: theme.color(.rowHover))
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        if row > rows.count { return automaticCell(automatic[row - rows.count - 1], column: tableColumn) }
        let isTrailing = row == rows.count
        let item = isTrailing ? nil : rows[row]
        switch tableColumn?.identifier {
        case columns.check.identifier:
            let box = NSButton(checkboxWithTitle: "", target: self, action: #selector(checkboxClicked))
            box.state = item?.isEnabled == true ? .on : .off
            box.isEnabled = !isTrailing
            box.bezelColor = theme.color(.accent)
            box.setAccessibilityLabel(item.map { "Send \($0.name.isEmpty ? "this row" : $0.name)" } ?? "")
            return centered(box)
        case columns.delete.identifier:
            guard !isTrailing else { return NSView() }
            let button = NSButton(image: NSImage(systemSymbolName: "minus.circle", accessibilityDescription: "Delete row")!,
                                  target: self, action: #selector(deleteClicked))
            button.isBordered = false
            button.contentTintColor = theme.color(.textTertiary)
            button.setAccessibilityLabel("Delete \(item?.name ?? "row")")
            button.identifier = Self.deleteID
            button.isHidden = true
            return centered(button)
        default:
            let isName = tableColumn?.identifier == columns.name.identifier
            if !isName, let item, files.indices.contains(row), files[row] {
                return fileCell(item.value)
            }
            let field = cellField()
            field.tag = isName ? 0 : 1
            field.stringValue = isName ? item?.name ?? "" : item?.value ?? ""
            field.toolTip = field.stringValue.isEmpty ? nil : field.stringValue
            field.textColor = theme.color(item?.isEnabled == false ? .textDisabled : .text)
            field.placeholderAttributedString = NSAttributedString(string: isName ? "Name" : allowsFiles ? "Value or file" : "Value", attributes: [
                .font: NSFont.systemFont(ofSize: 13), .foregroundColor: theme.color(.textTertiary),
            ])
            field.delegate = self
            field.wantsLayer = true
            field.layer?.cornerRadius = 4
            field.layer?.borderColor = theme.color(.focusRing).cgColor
            field.setAccessibilityLabel(isName ? "Name" : "Value")
            return cellView(field)
        }
    }

    /// No checkbox, no delete, not editable: only a row of the same name replaces it.
    private func automaticCell(_ header: AutomaticHeader, column: NSTableColumn?) -> NSView {
        guard column === columns.name || column === columns.value else { return NSView() }
        let field = cellField()
        field.isEditable = false
        field.stringValue = column === columns.name ? header.name : header.value ?? "calculated when sent"
        field.toolTip = field.stringValue
        field.textColor = theme.color(.textTertiary)
        field.setAccessibilityLabel(column === columns.name ? "Automatic header" : "Value")
        return cellView(field)
    }

    private func fileCell(_ path: String) -> NSView {
        let chip = FileChip(path: path, isMissing: path == missingFile, theme: theme)
        let cell = NSView()
        chip.translatesAutoresizingMaskIntoConstraints = false
        cell.addSubview(chip)
        NSLayoutConstraint.activate([
            chip.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 4),
            chip.trailingAnchor.constraint(lessThanOrEqualTo: cell.trailingAnchor, constant: -4),
            chip.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
        ])
        return cell
    }

    private func cellField() -> NSTextField {
        let field = NSTextField()
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        field.lineBreakMode = .byTruncatingTail
        field.usesSingleLineMode = true
        field.cell?.isScrollable = false
        return field
    }

    private func cellView(_ field: NSTextField) -> NSTableCellView {
        let cell = NSTableCellView()
        cell.textField = field
        field.translatesAutoresizingMaskIntoConstraints = false
        cell.addSubview(field)
        NSLayoutConstraint.activate([
            field.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 4),
            field.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -4),
            field.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
        ])
        return cell
    }

    private func centered(_ control: NSView) -> NSView {
        let cell = NSView()
        control.translatesAutoresizingMaskIntoConstraints = false
        cell.addSubview(control)
        NSLayoutConstraint.activate([
            control.centerXAnchor.constraint(equalTo: cell.centerXAnchor),
            control.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
        ])
        return cell
    }
}

/// A multipart file value: 20 pt, `backgroundRecessed`, `border`, a document glyph and the file
/// name, the full path in the tooltip. Missing at send: `error` border and text, a warning glyph.
final class FileChip: NSView {
    let nameLabel: NSTextField
    let isMissing: Bool

    init(path: String, isMissing: Bool, theme: ThemeEnvironment) {
        self.isMissing = isMissing
        nameLabel = NSTextField(labelWithString: (path as NSString).lastPathComponent)
        super.init(frame: .zero)
        let ink = theme.color(isMissing ? .error : .text)
        wantsLayer = true
        layer?.cornerRadius = 4
        layer?.borderWidth = 1
        layer?.borderColor = theme.color(isMissing ? .error : .border).cgColor
        layer?.backgroundColor = theme.color(.backgroundRecessed).cgColor
        toolTip = path
        nameLabel.font = .systemFont(ofSize: 11)
        nameLabel.textColor = ink
        nameLabel.lineBreakMode = .byTruncatingTail
        nameLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let glyph = NSImageView(image: NSImage(systemSymbolName: isMissing ? "exclamationmark.triangle" : "doc",
                                               accessibilityDescription: isMissing ? "Missing file" : "File")!)
        glyph.symbolConfiguration = .init(pointSize: 10, weight: .regular)
        glyph.contentTintColor = ink
        let stack = NSStackView(views: [glyph, nameLabel])
        stack.spacing = 4
        stack.edgeInsets = NSEdgeInsets(top: 0, left: 6, bottom: 0, right: 6)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 20),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        setAccessibilityElement(true)
        setAccessibilityRole(.staticText)
        setAccessibilityLabel(isMissing ? "\(nameLabel.stringValue), missing" : nameLabel.stringValue)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }
}

/// Space toggles the selected row, Delete removes it, Return edits its name.
final class KeyTableView: NSTableView {
    weak var keys: KeyValueTable?

    /// Grid lines stop at the last row instead of filling the empty space below it.
    override func drawGrid(inClipRect clipRect: NSRect) {
        let used = numberOfRows > 0 ? rect(ofRow: numberOfRows - 1).maxY : 0
        super.drawGrid(inClipRect: clipRect.intersection(NSRect(x: 0, y: 0, width: bounds.width, height: used)))
    }

    override func keyDown(with event: NSEvent) {
        let row = selectedRow
        guard row >= 0, let keys else { return super.keyDown(with: event) }
        switch event.keyCode {
        case 49: keys.toggle(row: row)
        case 51, 117: keys.delete(row: row)
        case 36, 76: if row <= keys.rows.count { editColumn(1, row: row, with: nil, select: true) }
        default: super.keyDown(with: event)
        }
    }
}

/// `rowHover` under the pointer, and the row's delete button shown only then.
private final class HoverRowView: NSTableRowView {
    private let hover: NSColor
    private var isHovered = false {
        didSet {
            needsDisplay = true
            for case let button as NSButton in subviews.flatMap(\.subviews) where button.identifier == KeyValueTable.deleteID {
                button.isHidden = !isHovered
            }
        }
    }

    init(hover: NSColor) {
        self.hover = hover
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect], owner: self))
    }

    override func mouseEntered(with event: NSEvent) { isHovered = true }
    override func mouseExited(with event: NSEvent) { isHovered = false }

    override func drawBackground(in dirtyRect: NSRect) {
        guard isHovered else { return super.drawBackground(in: dirtyRect) }
        hover.setFill()
        bounds.fill()
    }
}

/// "Name" / "Value" in `textTertiary` 11 semibold on `backgroundRecessed`.
private final class HeaderCell: NSTableHeaderCell {
    private let theme: ThemeEnvironment

    init(theme: ThemeEnvironment) {
        self.theme = theme
        super.init(textCell: "")
    }

    @available(*, unavailable)
    required init(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func draw(withFrame cellFrame: NSRect, in controlView: NSView) {
        theme.color(.backgroundRecessed).setFill()
        cellFrame.fill()
        theme.color(.border).setFill()
        NSRect(x: cellFrame.minX, y: cellFrame.maxY - 1, width: cellFrame.width, height: 1).fill()
        NSRect(x: cellFrame.maxX - 1, y: cellFrame.minY, width: 1, height: cellFrame.height).fill()
        let title = NSAttributedString(string: stringValue, attributes: [
            .font: NSFont.systemFont(ofSize: 11, weight: .semibold), .foregroundColor: theme.color(.textTertiary),
        ])
        title.draw(at: NSPoint(x: cellFrame.minX + 8, y: cellFrame.midY - title.size().height / 2))
    }
}

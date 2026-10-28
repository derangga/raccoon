import AppKit
import RaccoonDomain

/// The key/value table shared by Params, Headers, Cookies, form-urlencoded and multipart
/// (design-system.md §6). Rows come in through `setRows`; every edit goes out through
/// `onChange`, already applied, so the owner stores it and sets it back without a reload.
final class KeyValueTable: NSView, NSTableViewDataSource, NSTableViewDelegate, NSTextFieldDelegate {
    static let deleteID = NSUserInterfaceItemIdentifier("delete")
    var onChange: ([Row]) -> Void = { _ in }
    private(set) var rows: [Row] = []
    /// Headers only: what is sent that no row sets, above the rows, read-only. Table row `r` is
    /// `automatic[r]` while `r < lead`, then `rows[r - lead]`, then the trailing empty row.
    private var automatic: [AutomaticHeader] = []
    private var lead: Int { automatic.count }
    /// The automatic rows above the user's, for the table view's keys.
    var leadRows: Int { lead }
    private let theme: ThemeEnvironment
    /// Multipart only: a value can be a file, drawn as a chip, picked or dropped onto a row.
    private let allowsFiles: Bool
    /// Beside `rows`, one per row: whether its value is a file path.
    private(set) var files: [Bool] = []
    /// The file a send could not read, drawn with its chip in `error`.
    var missingFile: String? {
        didSet { if missingFile != oldValue { table.reloadData() } }
    }
    /// What the cells colour `{{name}}` by; the window's Variables, set on every render.
    private var kinds: VariableKinds?
    let table = KeyTableView()
    private let scroll = ForwardingScrollView()
    /// True where the owner scrolls: the table is as tall as its rows and hands the wheel on.
    var forwardsScrolling: Bool {
        get { scroll.forwards }
        set { scroll.forwards = newValue }
    }
    private let columns = (check: NSTableColumn(identifier: .init("check")), name: NSTableColumn(identifier: .init("name")),
                           value: NSTableColumn(identifier: .init("value")), delete: NSTableColumn(identifier: .init("delete")))

    init(theme: ThemeEnvironment, allowsFiles: Bool = false) {
        self.theme = theme
        self.allowsFiles = allowsFiles
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 6
        layer?.borderWidth = 1
        layer?.masksToBounds = true

        for (column, title, width) in [(columns.check, "", 30.0), (columns.name, "Name", 120), (columns.value, "Value", 200), (columns.delete, "", 30)] {
            column.headerCell = KeyHeaderCell(theme: theme, ruleBefore: column === columns.value)
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
        table.gridStyleMask = [.solidHorizontalGridLineMask]
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

        // The cells and row views are made in each reload, so a reload recolours them.
        theme.paint(self) { view, theme in
            view.layer?.borderColor = theme.color(.border).cgColor
            view.table.gridColor = theme.color(.border)
            view.table.backgroundColor = theme.color(.background)
            view.table.headerView?.needsDisplay = true
            view.table.reloadData()
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
            table.insertRows(at: IndexSet(integer: lead + rows.count), withAnimation: [])
            invalidateIntrinsicContentSize()
        } else {
            rows[row].value = path
            files[row] = true
        }
        onChange(rows)
        table.reloadData(forRowIndexes: IndexSet(integer: lead + row), columnIndexes: IndexSet(integersIn: 0..<4))
    }

    @objc private func chooseFile() {
        let clicked = table.clickedRow - lead
        let row = clicked >= 0 && clicked <= rows.count ? clicked : rows.count
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
        guard allowsFiles, row >= lead, row - lead <= rows.count else { return [] }
        tableView.setDropRow(row, dropOperation: .on)
        return .copy
    }

    func tableView(_ tableView: NSTableView, acceptDrop info: any NSDraggingInfo, row: Int, dropOperation: NSTableView.DropOperation) -> Bool {
        let urls = info.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL]
        guard let url = urls?.first else { return false }
        setFile(url.path, at: row - lead)
        return true
    }

    /// Recolours the cells on screen in place, so a field being edited keeps its editor; cells
    /// made later take `kinds` when they are made.
    func setKinds(_ new: VariableKinds) {
        guard new != kinds else { return }
        kinds = new
        table.enumerateAvailableRowViews { rowView, row in
            guard row >= lead else { return }
            for column in 0..<rowView.numberOfColumns {
                ((rowView.view(atColumn: column) as? NSTableCellView)?.textField as? KeyField)?.kinds = new
            }
        }
    }

    /// Replaces only the automatic rows, so a field being edited below them keeps its editor.
    func setAutomaticRows(_ new: [AutomaticHeader]) {
        guard new != automatic else { return }
        table.beginUpdates()
        table.removeRows(at: IndexSet(integersIn: 0..<lead), withAnimation: [])
        automatic = new
        table.insertRows(at: IndexSet(integersIn: 0..<lead), withAnimation: [])
        table.endUpdates()
        invalidateIntrinsicContentSize()
    }

    /// As tall as its rows; the owner caps it at the pane, and past that the rows scroll.
    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: 24 + CGFloat(table.numberOfRows) * table.rowHeight)
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
            table.insertRows(at: IndexSet(integer: lead + rows.count), withAnimation: [])
            invalidateIntrinsicContentSize()
        }
        onChange(rows)
    }

    func toggle(row: Int) {
        guard rows.indices.contains(row) else { return }
        apply(Rows.toggle(at: row, in: rows))
        table.reloadData(forRowIndexes: IndexSet(integer: lead + row), columnIndexes: IndexSet(integersIn: 0..<4))
    }

    func delete(row: Int) {
        guard rows.indices.contains(row) else { return }
        rows = Rows.delete(at: row, in: rows)
        if files.indices.contains(row) { files.remove(at: row) }
        table.removeRows(at: IndexSet(integer: lead + row), withAnimation: [])
        invalidateIntrinsicContentSize()
        onChange(rows)
    }

    @objc private func checkboxClicked(_ sender: NSButton) { toggle(row: table.row(for: sender) - lead) }
    @objc private func deleteClicked(_ sender: NSButton) { delete(row: table.row(for: sender) - lead) }

    func controlTextDidChange(_ notification: Notification) {
        guard let field = notification.object as? NSTextField else { return }
        let row = table.row(for: field) - lead
        guard row >= 0 else { return }
        let wasTrailing = row == rows.count
        apply(field.tag == 0 ? Rows.setName(field.stringValue, at: row, in: rows) : Rows.setValue(field.stringValue, at: row, in: rows))
        field.toolTip = field.stringValue
        // The trailing row became a real row: give it its checkbox and its delete button.
        if wasTrailing { activate(row: lead + row) } else if field.tag == 0 { relabel(row: lead + row) }
    }

    /// The trailing row became a real row: its checkbox and delete button come alive. Updated in
    /// place, because reloading the row's cells ends the editing of the field being typed in.
    private func activate(row: Int) {
        if let box = table.view(atColumn: 0, row: row, makeIfNecessary: false)?.subviews.first as? NSButton {
            box.isEnabled = true
            box.state = .on
        }
        if let button = table.view(atColumn: 3, row: row, makeIfNecessary: false)?.subviews.first as? NSButton {
            button.isEnabled = true
        }
        relabel(row: row)
        (table.rowView(atRow: row, makeIfNecessary: false) as? KeyRowView)?.showDeleteIfHovered()
    }

    /// The checkbox and delete button name the row as it is now, after every keystroke.
    private func relabel(row: Int) {
        guard rows.indices.contains(row - lead) else { return }
        let name = rows[row - lead].name
        (table.view(atColumn: 0, row: row, makeIfNecessary: false)?.subviews.first as? NSButton)?
            .setAccessibilityLabel("Send \(name.isEmpty ? "this row" : name)")
        (table.view(atColumn: 3, row: row, makeIfNecessary: false)?.subviews.first as? NSButton)?
            .setAccessibilityLabel("Delete \(name.isEmpty ? "row" : name)")
    }

    // MARK: Data source and cells

    func numberOfRows(in tableView: NSTableView) -> Int { rows.count + 1 + automatic.count }

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        KeyRowView(hover: theme.color(.rowHover), selection: theme.color(.selection), rule: theme.color(.border)) { [weak self] in
            self?.table.rect(ofColumn: 2).minX ?? 0
        }
    }

    /// An automatic row is read-only and has nothing to toggle or delete, so it is not selected.
    func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool { row >= lead }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        if row < lead { return automaticCell(automatic[row], column: tableColumn) }
        let row = row - lead
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
            let button = NSButton(image: NSImage(systemSymbolName: "minus.circle", accessibilityDescription: "Delete row")!,
                                  target: self, action: #selector(deleteClicked))
            button.isBordered = false
            button.contentTintColor = theme.color(.textTertiary)
            // The trailing row has the button too, inert until typing makes it a row.
            button.isEnabled = !isTrailing
            button.setAccessibilityLabel("Delete \(item?.name ?? "row")")
            button.identifier = Self.deleteID
            button.isHidden = true
            return centered(button)
        default:
            let isName = tableColumn?.identifier == columns.name.identifier
            if !isName, let item, files.indices.contains(row), files[row] {
                return fileCell(item.value)
            }
            let field = Self.cellField(theme: theme)
            field.tag = isName ? 0 : 1
            field.stringValue = isName ? item?.name ?? "" : item?.value ?? ""
            field.toolTip = field.stringValue.isEmpty ? nil : field.stringValue
            field.textColor = theme.color(item?.isEnabled == false ? .textDisabled : .text)
            field.isDisabledRow = item?.isEnabled == false
            field.kinds = kinds
            field.highlight()
            field.placeholderAttributedString = NSAttributedString(string: isName ? "Name" : allowsFiles ? "Value or file" : "Value", attributes: [
                .font: NSFont.systemFont(ofSize: 13), .foregroundColor: theme.color(.textTertiary).withAlphaComponent(0.6),
            ])
            field.delegate = self
            field.setAccessibilityLabel(isName ? "Name" : "Value")
            return Self.cellView(field, theme: theme)
        }
    }

    /// A locked checked box, no delete, not editable: only a row of the same name replaces it.
    private func automaticCell(_ header: AutomaticHeader, column: NSTableColumn?) -> NSView {
        if column === columns.check {
            // Sent whatever the user does, so the box is checked and cannot be changed.
            let box = NSButton(checkboxWithTitle: "", target: nil, action: nil)
            box.state = .on
            box.isEnabled = false
            box.toolTip = "Always sent. Add a row with the same name to replace it."
            box.setAccessibilityLabel("\(header.name) is always sent")
            return centered(box)
        }
        guard column === columns.name || column === columns.value else { return NSView() }
        let field = Self.cellField(theme: theme)
        field.isEditable = false
        field.stringValue = column === columns.name ? header.name : header.value ?? "calculated when sent"
        field.toolTip = field.stringValue
        field.textColor = theme.color(.textTertiary)
        field.setAccessibilityLabel(column === columns.name ? "Automatic header" : "Value")
        return Self.cellView(field, theme: theme)
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

    static func cellField(theme: ThemeEnvironment) -> KeyField {
        let field = KeyField()
        field.theme = theme
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        field.lineBreakMode = .byTruncatingTail
        field.usesSingleLineMode = true
        field.cell?.isScrollable = false
        return field
    }

    static func cellView(_ field: NSTextField, theme: ThemeEnvironment) -> NSTableCellView {
        EditableCellView(field: field, inset: 4, centersOwnText: true, ring: theme.color(.focusRing), fill: theme.color(.background))
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

/// A cell's text field: its text and its editor sit 4 pt inside the box, so the 2 pt editing ring
/// does not touch the letters.
final class KeyField: VariableField {
    override class var cellClass: AnyClass? {
        get { KeyFieldCell.self }
        set {}
    }
}

extension NSTextFieldCell {
    /// One line tall in the middle of `box`: a text cell draws at the top of a box taller than its text.
    func oneLine(centeredIn box: NSRect) -> NSRect {
        var box = box
        let line = ceil(max(font?.boundingRectForFont.height ?? 0, placeholderAttributedString?.size().height ?? 0))
        if line > 0, line < box.height {
            box.origin.y += ((box.height - line) / 2).rounded()
            box.size.height = line
        }
        return box
    }
}

final class KeyFieldCell: VariableFieldCell {
    private static let inset: CGFloat = 4

    /// Inset 4 pt either side, and one line tall in the middle of the box: a text cell draws at
    /// the top of a box taller than its text.
    override func drawingRect(forBounds rect: NSRect) -> NSRect {
        oneLine(centeredIn: super.drawingRect(forBounds: rect).insetBy(dx: Self.inset, dy: 0))
    }

    override func edit(withFrame rect: NSRect, in controlView: NSView, editor: NSText, delegate: Any?, event: NSEvent?) {
        super.edit(withFrame: drawingRect(forBounds: rect), in: controlView, editor: editor, delegate: delegate, event: event)
    }

    override func select(withFrame rect: NSRect, in controlView: NSView, editor: NSText, delegate: Any?, start: Int, length: Int) {
        super.select(withFrame: drawingRect(forBounds: rect), in: controlView, editor: editor, delegate: delegate, start: start, length: length)
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

    /// AppKit asks the table whether a click may go straight to a field, and says no unless the row can
    /// be selected: a click then selects the row and edits. A table with no `keys` (Path Variables) never
    /// selects, so its Value cells would never take a click; say yes.
    override func validateProposedFirstResponder(_ responder: NSResponder, for event: NSEvent?) -> Bool {
        keys == nil && responder is NSTextField ? true : super.validateProposedFirstResponder(responder, for: event)
    }

    /// Grid lines stop at the last row instead of filling the empty space below it. The vertical
    /// rule between Name and Value is drawn by each row view: a row view paints over the table.
    override func drawGrid(inClipRect clipRect: NSRect) {
        let used = numberOfRows > 0 ? rect(ofRow: numberOfRows - 1).maxY : 0
        super.drawGrid(inClipRect: clipRect.intersection(NSRect(x: 0, y: 0, width: bounds.width, height: used)))
    }

    override func keyDown(with event: NSEvent) {
        guard let keys, selectedRow - keys.leadRows >= 0 else { return super.keyDown(with: event) }
        let row = selectedRow - keys.leadRows
        switch event.keyCode {
        case 49: keys.toggle(row: row)
        case 51, 117: keys.delete(row: row)
        case 36, 76: if row <= keys.rows.count { editColumn(1, row: selectedRow, with: nil, select: true) }
        default: super.keyDown(with: event)
        }
    }
}

/// `rowHover` under the pointer, and the row's delete button shown only then.
final class KeyRowView: NSTableRowView {
    private let hover: NSColor
    private let selection: NSColor
    private let rule: NSColor
    /// Where the Value column starts, in the row's coordinates.
    private let ruleX: () -> CGFloat
    private var isHovered = false {
        didSet {
            needsDisplay = true
            showDeleteIfHovered()
        }
    }

    func showDeleteIfHovered() {
        for case let button as NSButton in subviews.flatMap(\.subviews) where button.identifier == KeyValueTable.deleteID {
            button.isHidden = !(isHovered && button.isEnabled)
        }
    }

    init(hover: NSColor, selection: NSColor, rule: NSColor, ruleX: @escaping () -> CGFloat) {
        self.hover = hover
        self.selection = selection
        self.rule = rule
        self.ruleX = ruleX
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

    /// The `selection` fill, not the system accent: the row's text keeps its own colors on it.
    override func drawSelection(in dirtyRect: NSRect) {
        selection.setFill()
        bounds.fill()
    }

    override var isEmphasized: Bool {
        get { false }
        set {}
    }

    /// The one vertical rule, between Name and Value, on top of the fill and under the cells.
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        rule.setFill()
        NSRect(x: ruleX(), y: 0, width: 1, height: bounds.height).fill()
    }

    override func drawBackground(in dirtyRect: NSRect) {
        guard isHovered else { return super.drawBackground(in: dirtyRect) }
        hover.setFill()
        bounds.fill()
    }
}

/// "Name" / "Value" in `textTertiary` 11 semibold on `backgroundRecessed`.
final class KeyHeaderCell: NSTableHeaderCell {
    private let theme: ThemeEnvironment
    private let ruleBefore: Bool

    init(theme: ThemeEnvironment, ruleBefore: Bool) {
        self.theme = theme
        self.ruleBefore = ruleBefore
        super.init(textCell: "")
    }

    @available(*, unavailable)
    required init(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func draw(withFrame cellFrame: NSRect, in controlView: NSView) {
        theme.color(.backgroundRecessed).setFill()
        cellFrame.fill()
        theme.color(.border).setFill()
        NSRect(x: cellFrame.minX, y: cellFrame.maxY - 1, width: cellFrame.width, height: 1).fill()
        if ruleBefore { NSRect(x: cellFrame.minX, y: cellFrame.minY, width: 1, height: cellFrame.height).fill() }
        let title = NSAttributedString(string: stringValue, attributes: [
            .font: NSFont.systemFont(ofSize: 11, weight: .semibold), .foregroundColor: theme.color(.textTertiary),
        ])
        title.draw(at: NSPoint(x: cellFrame.minX + 8, y: cellFrame.midY - title.size().height / 2))
    }
}

/// A scroll view that, when told to, hands the wheel to its owner's scroll view: a table as tall as
/// its rows inside a pane that scrolls.
final class ForwardingScrollView: NSScrollView {
    var forwards = false

    override func scrollWheel(with event: NSEvent) {
        if forwards { nextResponder?.scrollWheel(with: event) } else { super.scrollWheel(with: event) }
    }
}

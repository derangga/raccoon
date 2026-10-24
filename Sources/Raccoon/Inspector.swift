import AppKit
import Observation
import RaccoonDomain

/// The inspector's content (design-system §6 Inspector): a 34 pt header with the pane's name and
/// the Variables / Curl switch, the Variables pane, and its Edit Environments… footer. It follows
/// the selected Tab, the Environments, Globals and the Active Environment as they change.
final class InspectorViewController: NSViewController {
    private let window: WindowModel
    private let theme: ThemeEnvironment
    let paneTitle = NSTextField(labelWithString: "Variables")
    let paneSwitch: SegmentedControl
    let variables: VariablesPaneView
    let editButton = NSButton(title: "", target: nil, action: nil)
    /// The Variables pane's Edit Environments… bar; the Curl pane has its own.
    private let footer = NSView()
    var onEditEnvironments: (() -> Void)?

    init(window: WindowModel, theme: ThemeEnvironment) {
        self.window = window
        self.theme = theme
        paneSwitch = SegmentedControl(labels: ["Variables", "Curl"], symbols: ["curlybraces", "terminal"], theme: theme)
        variables = VariablesPaneView(theme: theme)
        super.init(nibName: nil, bundle: nil)
        paneSwitch.selectedSegment = 0
        paneSwitch.target = self
        paneSwitch.action = #selector(switchPane)
        // shortcut: the Curl pane is not built yet, so its segment is disabled and segment 1 shows
        // an empty pane. Enable the segment when the Curl pane fills that slot in showPane.
        paneSwitch.setEnabled(false, forSegment: 1)
        paneSwitch.setAccessibilityLabel("Inspector pane")
        paneTitle.font = .systemFont(ofSize: 12, weight: .semibold)
        editButton.isBordered = false
        editButton.wantsLayer = true
        editButton.layer?.cornerRadius = 6
        editButton.layer?.borderWidth = 1
        editButton.target = self
        editButton.action = #selector(editEnvironments)
        variables.onEdit = { [weak self] entry, group, text in self?.write(entry, group: group, text) }
        variables.reload = { [weak self] in self?.refresh() }
        observe()
    }

    /// An edited value, through the window as the Environments sheet writes (variables.md): the
    /// line to show under the row when it was not saved.
    private func write(_ entry: VariablesPane.Entry, group: VariablesPane.Group, _ text: String) -> String? {
        let active = window.variables.active?.name
        let set = group == .active ? active : nil
        switch (entry.shown, entry.index) {
        case (.secret, let index?):
            do throws(SecretError) {
                try window.setSecretValue(text, at: index, in: set)
            } catch {
                return EnvironmentsSheet.message(error)
            }
        case (.value, let index?):
            do throws(StoreError) {
                try window.setValue(text, for: entry.name, at: index, in: set)
            } catch {
                return "Not saved. " + EnvironmentsSheet.sentence(EnvironmentsSheet.reason(error))
            }
        case (.usedIn, _):
            do throws(StoreError) {
                try window.define(entry.name, value: text, in: active)
            } catch {
                return "Not saved. " + EnvironmentsSheet.sentence(EnvironmentsSheet.reason(error))
            }
        case (.secret, nil), (.value, nil):
            preconditionFailure("VariablesPane gives every defined row its index")
        }
        return nil
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func loadView() {
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 280, height: 600))
        let header = NSView()
        let headerRule = ThemedView(theme: theme, fill: .border)
        let footerRule = ThemedView(theme: theme, fill: .border)
        for view in [header, variables, footer, headerRule, footerRule, paneTitle, paneSwitch, editButton] {
            view.translatesAutoresizingMaskIntoConstraints = false
        }
        header.addSubview(paneTitle)
        header.addSubview(paneSwitch)
        footer.addSubview(editButton)
        for view in [header, variables, footer, headerRule, footerRule] { root.addSubview(view) }
        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: root.topAnchor),
            header.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            header.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            header.heightAnchor.constraint(equalToConstant: 34),
            paneTitle.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: 12),
            paneTitle.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            paneSwitch.trailingAnchor.constraint(equalTo: header.trailingAnchor, constant: -8),
            paneSwitch.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            headerRule.topAnchor.constraint(equalTo: header.bottomAnchor),
            headerRule.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            headerRule.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            headerRule.heightAnchor.constraint(equalToConstant: 1),
            variables.topAnchor.constraint(equalTo: headerRule.bottomAnchor),
            variables.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            variables.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            variables.bottomAnchor.constraint(equalTo: footerRule.topAnchor),
            footerRule.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            footerRule.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            footerRule.heightAnchor.constraint(equalToConstant: 1),
            footerRule.bottomAnchor.constraint(equalTo: footer.topAnchor),
            footer.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            footer.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            footer.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            footer.heightAnchor.constraint(equalToConstant: 40),
            editButton.trailingAnchor.constraint(equalTo: footer.trailingAnchor, constant: -12),
            editButton.centerYAnchor.constraint(equalTo: footer.centerYAnchor),
            editButton.heightAnchor.constraint(equalToConstant: 24),
        ])
        view = root
    }

    /// "Variables in request": the Variables pane, with `name`'s resolving row selected and in view.
    func reveal(_ name: VariableName) {
        showPane(0)
        // A value being edited is saved first, as clicking away saves it.
        variables.endEditing()
        variables.select(name)
        // A pane that just opened has its width only after layout; the rows are placed by it.
        view.layoutSubtreeIfNeeded()
        refresh()
        variables.scrollToSelection()
    }

    /// Renders now, and again when anything it read changes.
    private func observe() {
        withObservationTracking { refresh() } onChange: { [weak self] in
            Task { @MainActor in self?.observe() }
        }
    }

    private func refresh() {
        let (active, globals) = window.variables
        let definition = window.selectedTab?.tab.definition ?? .empty
        variables.render(VariablesPane(definition: definition, active: active, globals: globals))
        paneTitle.textColor = theme.color(.text)
        editButton.attributedTitle = NSAttributedString(string: "Edit Environments…", attributes: [
            .font: NSFont.systemFont(ofSize: 12), .foregroundColor: theme.color(.text),
        ])
        editButton.layer?.backgroundColor = theme.color(.background).cgColor
        editButton.layer?.borderColor = theme.color(.border).cgColor
        editButton.removeConstraints(editButton.constraints.filter { $0.firstAttribute == .width })
        editButton.widthAnchor.constraint(equalToConstant: (editButton.attributedTitle.size().width + 20).rounded(.up)).isActive = true
    }

    @objc private func editEnvironments() { onEditEnvironments?() }

    @objc private func switchPane() { showPane(paneSwitch.selectedSegment) }

    /// The pane under the header: 0 is Variables, 1 is Curl. The header's title names it.
    func showPane(_ index: Int) {
        paneSwitch.selectedSegment = index
        paneTitle.stringValue = paneSwitch.label(forSegment: index) ?? ""
        variables.isHidden = index != 0
        footer.isHidden = index != 0
    }
}

/// The Variables pane (design-system §6 Inspector, boards 04, 11, 14): a table of group titles
/// and 24 pt rows of name and value. One click on a value edits it in place; Return or clicking
/// away saves it through `onEdit`, Esc puts it back.
final class VariablesPaneView: NSView, NSTextFieldDelegate {
    /// One row as drawn, for the grouping, selection and edit checks.
    struct Line {
        let name: String
        /// The value, "Secret", or where an undefined name is used.
        let value: String
        let isStruck: Bool
        let isSelected: Bool
        /// "Not saved. …" under the row.
        let error: String?
    }

    /// Writes an edit; returns the line to show under the row when it was not saved.
    var onEdit: ((VariablesPane.Entry, VariablesPane.Group, String) -> String?)?
    /// Renders again from the window, after an edit.
    var reload: (() -> Void)?

    private let theme: ThemeEnvironment
    private let scroll = NSScrollView()
    private let document = PaneDocument()
    private(set) var titles: [String] = []
    private(set) var rows: [Line] = []
    private(set) var note: String?
    /// "No Globals." when there are none.
    private(set) var emptyGlobals: String?
    private var shown: VariablesPane?
    /// The row the link or a click chose, by name and group so it outlives a render; no group
    /// means the row that resolves the name.
    private var selection: (name: VariableName, group: VariablesPane.Group?)?
    /// Each row's entry and group, by row index (a field's tag).
    private var cells: [(entry: VariablesPane.Entry, group: VariablesPane.Group)] = []
    /// Each row's frame in the document, its selection fill and its value field, by row index.
    private(set) var rowFrames: [NSRect] = []
    private var fills: [NSView] = []
    private var fields: [NSTextField] = []
    private var restFrames: [NSRect] = []
    /// What shows at rest behind a secret's or an undefined name's empty field.
    private var restViews: [Int: NSView] = [:]
    private var errors: [String: String] = [:]
    private var editing: Int?
    private var cancelled = false
    private var selectedRect: NSRect?
    private var renderedWidth: CGFloat = 0

    private static let side: CGFloat = 12
    private static let rowHeight: CGFloat = 24

    init(theme: ThemeEnvironment) {
        self.theme = theme
        super.init(frame: NSRect(x: 0, y: 0, width: 280, height: 400))
        scroll.frame = bounds
        scroll.autoresizingMask = [.width, .height]
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.documentView = document
        addSubview(scroll)
        document.onClick = { [weak self] point in
            guard let self, let row = self.rowFrames.firstIndex(where: { $0.contains(point) }) else { return }
            self.select(row: row)
        }
    }

    var documentView: NSView { document }
    /// The row whose value is being edited.
    var editingRow: Int? { editing }

    /// "Variables in request": the row that resolves `name`, from the next render.
    func select(_ name: VariableName) {
        selection = (name, nil)
    }

    /// A click on a row, or on its value to edit it: that row is selected, the table stays as it is.
    func select(row: Int) {
        guard cells.indices.contains(row) else { return }
        selection = (cells[row].entry.name, cells[row].group)
        showSelection(row)
    }

    private func showSelection(_ selected: Int?) {
        selectedRect = selected.map { fills[$0].frame }
        for row in cells.indices {
            let isSelected = row == selected
            fills[row].isHidden = !isSelected
            if case .value = cells[row].entry.shown, !cells[row].entry.isOverridden, row != editing {
                fields[row].textColor = theme.color(isSelected ? .text : .textSecondary)
            }
            let line = rows[row]
            rows[row] = Line(name: line.name, value: line.value, isStruck: line.isStruck, isSelected: isSelected, error: line.error)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func layout() {
        super.layout()
        if let shown, editing == nil, scroll.contentSize.width != renderedWidth { render(shown) }
    }

    func scrollToSelection() {
        guard let selectedRect else { return }
        document.scrollToVisible(selectedRect)
    }

    /// Saves a value being edited, as clicking away does.
    func endEditing() {
        guard editing != nil else { return }
        window?.makeFirstResponder(nil)
    }

    /// Writes `text` as row `row`'s value: what Return or clicking away does. An unchanged value,
    /// or an empty secret or undefined one, writes nothing.
    func edit(row: Int, to text: String) {
        write(row: row, text)
        reload?()
    }

    private func write(row: Int, _ text: String) {
        guard cells.indices.contains(row) else { return }
        let (entry, group) = cells[row]
        let key = Self.key(entry, group)
        errors[key] = nil
        let unchanged = switch entry.shown {
        case .value(let value): value == text
        case .secret, .usedIn: text.isEmpty
        }
        if !unchanged, let error = onEdit?(entry, group, text) { errors[key] = error }
    }

    private static func key(_ entry: VariablesPane.Entry, _ group: VariablesPane.Group) -> String { "\(group)/\(entry.name.rawValue)" }

    // MARK: Editing

    /// A value field took focus: a click on it, or Tab into it. AppKit's begin-editing
    /// notification waits for the first keystroke, too late to hide "Secret" or "URL".
    private func startEditing(_ field: NSTextField) {
        editing = field.tag
        select(row: field.tag)
        restViews[field.tag]?.isHidden = true
        field.drawsBackground = true
        field.backgroundColor = theme.color(.background)
        // From the rest frame, so focusing the same cell again does not grow it again.
        field.frame = restFrames[field.tag].insetBy(dx: 0, dy: -2)
        if case .usedIn = cells[field.tag].entry.shown { field.placeholderString = "Value" }
        // A struck-out Global is edited as plain text.
        if let editor = field.currentEditor() as? NSTextView, let storage = editor.textStorage {
            storage.removeAttribute(.strikethroughStyle, range: NSRange(location: 0, length: storage.length))
            storage.addAttribute(.foregroundColor, value: theme.color(.text), range: NSRange(location: 0, length: storage.length))
        }
    }

    private func stopEditing(_ field: NSTextField) {
        guard restFrames.indices.contains(field.tag) else { return }
        field.frame = restFrames[field.tag]
        field.drawsBackground = false
        field.placeholderString = nil
        if field.stringValue.isEmpty { restViews[field.tag]?.isHidden = false }
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        switch selector {
        case #selector(NSResponder.cancelOperation(_:)):
            cancelled = true
            window?.makeFirstResponder(nil)
            return true
        case #selector(NSResponder.insertNewline(_:)):
            window?.makeFirstResponder(nil)
            return true
        default:
            return false
        }
    }

    /// Checked a turn later: a click on a field ends the edit its focus started and begins
    /// another in the same mouse-down, and a click on another value starts that one first. Only
    /// a field with no editor by then is done; the row is written unless Esc ended it.
    func controlTextDidEndEditing(_ notification: Notification) {
        guard let field = notification.object as? NSTextField else { return }
        let text = field.stringValue
        let cancelled = self.cancelled
        self.cancelled = false
        Task { @MainActor [weak self, weak field] in
            guard let self, let field, field.currentEditor() == nil else { return }
            if self.editing == field.tag { self.editing = nil }
            // Back to rest now: when another value took focus, the render below waits for it.
            self.stopEditing(field)
            if !cancelled { self.write(row: field.tag, text) }
            self.reload?()
        }
    }

    // MARK: Rendering

    /// While a value is being edited, the rows stay as they are and this render waits for the edit to end.
    func render(_ pane: VariablesPane) {
        shown = pane
        guard editing == nil else { return }
        let width = max(scroll.contentSize.width, 200)
        renderedWidth = scroll.contentSize.width
        let inner = width - 2 * Self.side
        let place = selection.flatMap { selection -> VariablesPane.Place? in
            let groups: [(VariablesPane.Group, [VariablesPane.Entry])] = [(.undefined, pane.undefined), (.active, pane.active), (.globals, pane.globals)]
            if let group = selection.group, let entries = groups.first(where: { $0.0 == group })?.1,
               let index = entries.firstIndex(where: { $0.name == selection.name }) {
                return VariablesPane.Place(group: group, index: index)
            }
            return pane.row(of: selection.name)
        }
        document.subviews.forEach { $0.removeFromSuperview() }
        titles = []
        rows = []
        cells = []
        rowFrames = []
        fills = []
        fields = []
        restFrames = []
        restViews = [:]
        note = nil
        emptyGlobals = nil
        selectedRect = nil
        var y: CGFloat = 10

        func label(_ text: String, font: NSFont, color: ColorToken) -> NSTextField {
            let label = NSTextField(labelWithString: text)
            label.font = font
            label.textColor = theme.color(color)
            label.lineBreakMode = .byTruncatingTail
            return label
        }
        func title(_ main: String, tag: String? = nil, color: ColorToken = .textTertiary, glyph: String? = nil) {
            let text = NSMutableAttributedString(string: main, attributes: [.font: NSFont.systemFont(ofSize: 11, weight: .semibold), .foregroundColor: theme.color(color)])
            if let tag { text.append(NSAttributedString(string: " · " + tag, attributes: [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: theme.color(color)])) }
            var x = Self.side
            if let glyph, let image = NSImage(systemSymbolName: glyph, accessibilityDescription: nil) {
                let icon = NSImageView(image: image)
                icon.symbolConfiguration = .init(pointSize: 11, weight: .regular)
                icon.contentTintColor = theme.color(color)
                icon.frame = NSRect(x: x, y: y, width: 12, height: 14)
                document.addSubview(icon)
                x += 18
            }
            let field = NSTextField(labelWithAttributedString: text)
            field.lineBreakMode = .byTruncatingTail
            field.frame = NSRect(x: x, y: y, width: width - Self.side - x, height: 14)
            document.addSubview(field)
            titles.append(text.string)
            y += 18
        }
        func row(_ entry: VariablesPane.Entry, group: VariablesPane.Group, index: Int) {
            let tag = cells.count
            cells.append((entry, group))
            let isSelected = place == VariablesPane.Place(group: group, index: index)
            let fill = ThemedView(theme: theme, fill: .selection)
            fill.frame = NSRect(x: Self.side - 4, y: y, width: inner + 8, height: Self.rowHeight - 1)
            fill.isHidden = !isSelected
            document.addSubview(fill)
            fills.append(fill)
            if isSelected { selectedRect = fill.frame }
            rowFrames.append(NSRect(x: 0, y: y, width: width, height: Self.rowHeight))
            let nameWidth = (inner * 0.46).rounded()
            let valueX = Self.side + nameWidth + 8
            // At rest where a label would sit; 4 pt taller while edited.
            let valueFrame = NSRect(x: valueX, y: y + 4, width: width - Self.side - valueX, height: 16)
            let mono = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
            let struck = entry.isOverridden
            let nameLabel = label(entry.name.rawValue, font: mono, color: struck ? .textDisabled : group == .undefined ? .variableUndefined : .text)
            nameLabel.frame = NSRect(x: Self.side, y: y + 4, width: nameWidth, height: 16)
            document.addSubview(nameLabel)
            if group == .undefined {
                // Undefined is never shown by colour alone: the wavy underline the editor draws.
                let name = NSMutableAttributedString(attributedString: nameLabel.attributedStringValue)
                name.addAttribute(.wavyUnderline, value: theme.color(.variableUndefined), range: NSRange(location: 0, length: name.length))
                nameLabel.attributedStringValue = name
                let waves = WaveOverlay(frame: nameLabel.bounds)
                waves.autoresizingMask = [.width, .height]
                nameLabel.addSubview(waves)
            }

            let field: NSTextField
            let shownValue: String
            switch entry.shown {
            case .value(let value):
                shownValue = value
                field = PaneField(string: value)
                field.textColor = theme.color(struck ? .textDisabled : isSelected ? .text : .textSecondary)
                field.toolTip = value
            case .secret:
                shownValue = "Secret"
                field = PaneSecureField(string: "")
                let lock = NSImageView(image: NSImage(systemSymbolName: "lock.fill", accessibilityDescription: nil)!)
                lock.symbolConfiguration = .init(pointSize: 10, weight: .regular)
                lock.contentTintColor = theme.color(struck ? .textDisabled : .variableSecret)
                let rest = NSStackView(views: [lock, label("Secret", font: .systemFont(ofSize: 12), color: struck ? .textDisabled : .variableSecret)])
                rest.spacing = 4
                rest.frame = valueFrame
                rest.alignment = .centerY
                restViews[tag] = rest
                document.addSubview(rest)
                field.textColor = theme.color(.text)
            case .usedIn(let sections):
                shownValue = sections.joined(separator: ", ")
                field = PaneField(string: "")
                let rest = label(shownValue, font: .systemFont(ofSize: 12), color: .variableUndefined)
                rest.frame = valueFrame
                restViews[tag] = rest
                document.addSubview(rest)
                field.textColor = theme.color(.text)
            }
            field.font = mono
            field.isBordered = false
            field.drawsBackground = false
            field.isEditable = true
            field.isSelectable = true
            field.usesSingleLineMode = true
            field.lineBreakMode = .byTruncatingTail
            field.focusRingType = .exterior
            field.tag = tag
            field.delegate = self
            (field as? PaneField)?.onFocus = { [weak self, weak field] in field.map { self?.startEditing($0) } }
            (field as? PaneSecureField)?.onFocus = { [weak self, weak field] in field.map { self?.startEditing($0) } }
            field.setAccessibilityLabel(entry.name.rawValue)
            if struck {
                let tail = NSMutableParagraphStyle()
                tail.lineBreakMode = .byTruncatingTail
                field.attributedStringValue = NSAttributedString(string: shownValue, attributes: [
                    .font: mono, .foregroundColor: theme.color(.textDisabled), .strikethroughStyle: NSUnderlineStyle.single.rawValue,
                    .paragraphStyle: tail,
                ])
                let name = NSMutableAttributedString(attributedString: nameLabel.attributedStringValue)
                name.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: NSRange(location: 0, length: name.length))
                nameLabel.attributedStringValue = name
                nameLabel.toolTip = "Overridden by \(pane.environment ?? "the Active Environment")"
            }
            field.frame = valueFrame
            document.addSubview(field)
            fields.append(field)
            restFrames.append(valueFrame)
            y += Self.rowHeight

            let error = errors[Self.key(entry, group)]
            if let error {
                let line = NSTextField(wrappingLabelWithString: error)
                line.font = .systemFont(ofSize: 11)
                line.textColor = theme.color(.error)
                let height = ceil(line.cell!.cellSize(forBounds: NSRect(x: 0, y: 0, width: inner, height: .greatestFiniteMagnitude)).height)
                line.frame = NSRect(x: Self.side, y: y, width: inner, height: height)
                line.setAccessibilityRole(.staticText)
                document.addSubview(line)
                y += height + 5
            }
            let rule = ThemedView(theme: theme, fill: .border)
            rule.frame = NSRect(x: Self.side, y: y - 1, width: inner, height: 1)
            document.addSubview(rule)
            rows.append(Line(name: entry.name.rawValue, value: shownValue, isStruck: struck, isSelected: isSelected, error: error))
        }

        if !pane.undefined.isEmpty {
            title("Not defined", tag: "used by this Tab", color: .variableUndefined, glyph: "exclamationmark.circle")
            for (index, entry) in pane.undefined.enumerated() { row(entry, group: .undefined, index: index) }
            y += 12
        }
        if let environment = pane.environment {
            title(environment, tag: "Active Environment")
            for (index, entry) in pane.active.enumerated() { row(entry, group: .active, index: index) }
        } else {
            title("No Environment", tag: "pick one in the toolbar")
        }
        y += 12
        title("Globals")
        for (index, entry) in pane.globals.enumerated() { row(entry, group: .globals, index: index) }
        if pane.globals.isEmpty {
            let text = "No Globals."
            let field = label(text, font: .systemFont(ofSize: 12), color: .textTertiary)
            field.frame = NSRect(x: Self.side, y: y + 4, width: inner, height: 16)
            document.addSubview(field)
            emptyGlobals = text
            y += Self.rowHeight
        }
        if let environment = pane.environment, pane.globals.contains(where: \.isOverridden) {
            let text = "A struck-out Global is overridden by \(environment). Disabled Variables are not listed."
            let field = NSTextField(wrappingLabelWithString: text)
            field.font = .systemFont(ofSize: 11)
            field.textColor = theme.color(.textTertiary)
            let height = ceil(field.cell!.cellSize(forBounds: NSRect(x: 0, y: 0, width: inner, height: .greatestFiniteMagnitude)).height)
            field.frame = NSRect(x: Self.side, y: y + 12, width: inner, height: height)
            document.addSubview(field)
            note = text
            y += 12 + height
        }
        document.frame = NSRect(x: 0, y: 0, width: width, height: max(y + 10, scroll.contentSize.height))
    }
}

/// A value cell that says when it takes focus.
private final class PaneField: NSTextField {
    var onFocus: (() -> Void)?

    override class var cellClass: AnyClass? {
        get { CenteredCell.self }
        set {}
    }

    override func becomeFirstResponder() -> Bool {
        let became = super.becomeFirstResponder()
        if became { onFocus?() }
        return became
    }
}

/// A secret's value cell: the same, typed into unseen.
private final class PaneSecureField: NSSecureTextField {
    var onFocus: (() -> Void)?

    override class var cellClass: AnyClass? {
        get { CenteredSecureCell.self }
        set {}
    }

    override func becomeFirstResponder() -> Bool {
        let became = super.becomeFirstResponder()
        if became { onFocus?() }
        return became
    }
}

/// The text line's rect, centered in `rect`: a field cell draws and edits at the top, so a cell
/// grown taller while edited would move its text.
private func centered(_ rect: NSRect, font: NSFont?) -> NSRect {
    guard let font else { return rect }
    let line = ceil(NSLayoutManager().defaultLineHeight(for: font))
    guard rect.height > line else { return rect }
    return NSRect(x: rect.minX, y: rect.minY + ((rect.height - line) / 2).rounded(.down), width: rect.width, height: line)
}

private final class CenteredCell: NSTextFieldCell {
    override func drawingRect(forBounds rect: NSRect) -> NSRect { centered(super.drawingRect(forBounds: rect), font: font) }
}

private final class CenteredSecureCell: NSSecureTextFieldCell {
    override func drawingRect(forBounds rect: NSRect) -> NSRect { centered(super.drawingRect(forBounds: rect), font: font) }
}

/// The pane's scrolled content, laid out top down. A click on it, off every value, ends an edit,
/// so clicking away saves.
private final class PaneDocument: NSView {
    /// A click off every value, in document coordinates: the pane selects the row under it.
    var onClick: ((NSPoint) -> Void)?

    override var isFlipped: Bool { true }

    /// Names, labels and fills take no clicks of their own, so a click anywhere on a row but its
    /// value lands here; a value field (and its editor) keeps its own.
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let hit = super.hitTest(point) else { return nil }
        let inValue = sequence(first: hit, next: \.superview).contains { ($0 as? NSTextField)?.isEditable == true }
        return inValue ? hit : self
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(nil)
        onClick?(convert(event.locationInWindow, from: nil))
    }
}

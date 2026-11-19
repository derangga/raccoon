import AppKit
import RaccoonDomain

/// The Body section: the Body Type Dropdown, the raw kind Dropdown, then "no body", the raw text
/// editor, the form table, the multipart table or the GraphQL Query and Variables editors side by side
/// (design-system.md §6 Body editor).
final class BodyPane: NSView, NSTextFieldDelegate {
    private var model: TabModel
    private let theme: ThemeEnvironment
    let typeDropdown: Dropdown
    let kindDropdown: Dropdown
    /// Each Dropdown is as wide as its title needs; set from `fittingWidth` when the title changes.
    private let typeWidth: NSLayoutConstraint
    private let kindWidth: NSLayoutConstraint
    let noneNote = NSTextField(labelWithString: "This request has no body.")
    /// Raw JSON and XML, on the Body Type row; manual, never on paste or save (Open UI question 15).
    let formatButton = PopButton()
    /// The GraphQL Variables, in their caption row; the same action, always enabled.
    let variablesFormatButton = PopButton()
    /// "Couldn't format: …" under the editor until the next edit.
    let formatError = NSTextField(labelWithString: "")
    /// The raw body's editor.
    private let rawEditor: BodyTextEditor
    var textView: NSTextView { rawEditor.textView }
    /// `background` with a 1 pt `border` and a 6 pt radius around the editor and its line numbers.
    var textBox: NSView { rawEditor }
    /// The GraphQL body: Operation Name on the Body Type row, Query beside Variables below it.
    let operationField = VariableField()
    private let operationLabel = NSTextField(labelWithString: "Operation Name")
    private let operationBox = NSView()
    let queryEditor: BodyTextEditor
    let variablesEditor: BodyTextEditor
    private let graphqlSplit: GraphQLSplitView
    let formTable: KeyValueTable
    let partsTable: KeyValueTable
    private var boxBottom = NSLayoutConstraint()
    private var splitBottom = NSLayoutConstraint()

    init(model: TabModel, theme: ThemeEnvironment) {
        self.model = model
        self.theme = theme
        typeDropdown = Dropdown(label: "Body Type", theme: theme, height: 24)
        kindDropdown = Dropdown(label: "Raw kind", theme: theme, height: 24)
        typeWidth = typeDropdown.widthAnchor.constraint(equalToConstant: 0)
        kindWidth = kindDropdown.widthAnchor.constraint(equalToConstant: 0)
        formTable = KeyValueTable(theme: theme)
        partsTable = KeyValueTable(theme: theme, allowsFiles: true)
        rawEditor = BodyTextEditor(theme: theme)
        queryEditor = BodyTextEditor(theme: theme)
        variablesEditor = BodyTextEditor(theme: theme)
        graphqlSplit = GraphQLSplitView(theme: theme)
        super.init(frame: .zero)
        formTable.onChange = { [weak self] in self?.model.tab.definition.body = .formURLEncoded($0) }
        partsTable.onChange = { [weak self] rows in
            guard let self else { return }
            model.tab.definition.body = .multipart(partsTable.parts(rows))
        }
        rawEditor.onChange = { [weak self] text in
            guard let self, case .raw(let kind, _) = model.tab.definition.body else { return }
            showFormatError(nil)
            model.tab.definition.body = .raw(kind, text)
        }
        queryEditor.onChange = { [weak self] text in self?.editGraphQL { $0.query = text } }
        variablesEditor.onChange = { [weak self] text in self?.editGraphQL { $0.variables = text } }
        queryEditor.placeholder = "{ \u{2026} }"
        variablesEditor.placeholder = "{}"
        buildControls()
        buildEditor()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// The GraphQL body's own fields are edited in place; any edit clears the format error.
    private func editGraphQL(_ change: (inout GraphQLBody) -> Void) {
        guard case .graphql(var body) = model.tab.definition.body else { return }
        showFormatError(nil)
        change(&body)
        model.tab.definition.body = .graphql(body)
    }

    // MARK: Layout

    private func buildControls() {
        let label = NSTextField(labelWithString: "Body Type")
        label.font = .systemFont(ofSize: 11)
        theme.paint(label) { $0.textColor = $1.color(.textTertiary) }
        typeWidth.isActive = true
        kindWidth.isActive = true
        typeDropdown.onPick = { [weak self] in self?.pickType($0) }
        kindDropdown.onPick = { [weak self] in self?.pickKind($0) }
        noneNote.font = .systemFont(ofSize: 12)
        theme.paint(noneNote) { $0.textColor = $1.color(.textTertiary) }

        for button in [formatButton, variablesFormatButton] { styleFormat(button) }
        variablesFormatButton.toolTip = "Format JSON (⇧⌥F)"
        formatError.font = .systemFont(ofSize: 11)
        theme.paint(formatError) { $0.textColor = $1.color(.error) }
        formatError.isHidden = true

        buildOperationName()
        let spacer = NSView()
        spacer.setContentHuggingPriority(.init(1), for: .horizontal)
        let row = NSStackView(views: [label, typeDropdown, kindDropdown, operationLabel, operationBox, spacer, formatButton])
        row.spacing = 8
        for view in [row, noneNote, formTable, partsTable] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        NSLayoutConstraint.activate([
            row.topAnchor.constraint(equalTo: topAnchor),
            row.leadingAnchor.constraint(equalTo: leadingAnchor),
            row.trailingAnchor.constraint(equalTo: trailingAnchor),
            row.heightAnchor.constraint(equalToConstant: 26),
            noneNote.centerXAnchor.constraint(equalTo: centerXAnchor),
            noneNote.centerYAnchor.constraint(equalTo: centerYAnchor, constant: 13),
            formTable.topAnchor.constraint(equalTo: row.bottomAnchor, constant: 8),
            formTable.leadingAnchor.constraint(equalTo: leadingAnchor),
            formTable.trailingAnchor.constraint(equalTo: trailingAnchor),
            formTable.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor),
            partsTable.topAnchor.constraint(equalTo: row.bottomAnchor, constant: 8),
            partsTable.leadingAnchor.constraint(equalTo: leadingAnchor),
            partsTable.trailingAnchor.constraint(equalTo: trailingAnchor),
            partsTable.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor),
        ])
    }

    /// Bordered, with a list glyph and "Format"; `setBody` gives ⇧⌥F to whichever one shows.
    private func styleFormat(_ button: PopButton) {
        button.isBordered = false
        button.wantsLayer = true
        button.layer?.cornerRadius = 6
        button.layer?.borderWidth = 1
        theme.paint(button) { button, theme in
            button.layer?.borderColor = theme.color(.border).cgColor
            button.layer?.backgroundColor = theme.color(.background).cgColor
            // The glyph is part of the title, so the pair centers as one and PopButton's 10 pt hold.
            let glyph = NSTextAttachment()
            glyph.image = NSImage(systemSymbolName: "list.bullet.indent", accessibilityDescription: nil)?
                .withSymbolConfiguration(.init(paletteColors: [theme.color(.text)]).applying(.init(pointSize: 11, weight: .regular)))
            let title = NSMutableAttributedString(attachment: glyph)
            title.append(NSAttributedString(string: " Format"))
            title.addAttributes([.font: NSFont.systemFont(ofSize: 12), .foregroundColor: theme.color(.text)], range: NSRange(location: 0, length: title.length))
            button.attributedTitle = title
        }
        button.setAccessibilityLabel("Format")
        button.target = self
        button.action = #selector(format)
        button.keyEquivalentModifierMask = [.shift, .option]
        button.refusesFirstResponder = true
        button.translatesAutoresizingMaskIntoConstraints = false
    }

    /// A 24 pt box like the pop-ups, holding the field; hidden unless the body is GraphQL.
    private func buildOperationName() {
        operationLabel.font = .systemFont(ofSize: 11)
        theme.paint(operationLabel) { $0.textColor = $1.color(.textTertiary) }
        operationBox.wantsLayer = true
        operationBox.layer?.cornerRadius = 6
        operationBox.layer?.borderWidth = 1
        theme.paint(operationBox) { box, theme in
            box.layer?.borderColor = theme.color(.border).cgColor
            box.layer?.backgroundColor = theme.color(.background).cgColor
        }
        let field = operationField
        field.theme = theme
        field.placeholderString = "Optional"
        field.setAccessibilityLabel("Operation Name")
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        theme.paint(field) { field, theme in
            field.textColor = theme.color(.text)
            field.placeholderAttributedString = NSAttributedString(string: field.placeholderString ?? "", attributes: [
                .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular), .foregroundColor: theme.color(.textTertiary),
            ])
        }
        field.cell?.isScrollable = true
        field.cell?.wraps = false
        field.delegate = self
        field.translatesAutoresizingMaskIntoConstraints = false
        operationBox.addSubview(field)
        operationBox.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            operationBox.widthAnchor.constraint(equalToConstant: 200),
            operationBox.heightAnchor.constraint(equalToConstant: 24),
            field.leadingAnchor.constraint(equalTo: operationBox.leadingAnchor, constant: 8),
            field.trailingAnchor.constraint(equalTo: operationBox.trailingAnchor, constant: -8),
            field.centerYAnchor.constraint(equalTo: operationBox.centerYAnchor),
        ])
    }

    private func buildEditor() {
        for (view, parent) in [(rawEditor, self as NSView), (graphqlSplit, self), (formatError, self)] {
            view.translatesAutoresizingMaskIntoConstraints = false
            parent.addSubview(view)
        }
        graphqlSplit.addArrangedSubview(captioned("Query", queryEditor, trailing: nil))
        graphqlSplit.addArrangedSubview(captioned("Variables", variablesEditor, trailing: variablesFormatButton))
        // The error line takes 20 pt from the bottom of the editors only while it shows.
        boxBottom = rawEditor.bottomAnchor.constraint(equalTo: bottomAnchor)
        splitBottom = graphqlSplit.bottomAnchor.constraint(equalTo: bottomAnchor)
        NSLayoutConstraint.activate([
            rawEditor.topAnchor.constraint(equalTo: topAnchor, constant: 34),
            rawEditor.leadingAnchor.constraint(equalTo: leadingAnchor),
            rawEditor.trailingAnchor.constraint(equalTo: trailingAnchor),
            boxBottom,
            graphqlSplit.topAnchor.constraint(equalTo: topAnchor, constant: 34),
            graphqlSplit.leadingAnchor.constraint(equalTo: leadingAnchor),
            graphqlSplit.trailingAnchor.constraint(equalTo: trailingAnchor),
            splitBottom,
            formatError.leadingAnchor.constraint(equalTo: leadingAnchor),
            formatError.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor),
            formatError.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    /// An 11 pt `textTertiary` caption in a 24 pt row over an editor, with a control at the row's
    /// trailing end.
    private func captioned(_ title: String, _ editor: BodyTextEditor, trailing control: NSView?) -> NSView {
        let caption = NSTextField(labelWithString: title)
        caption.font = .systemFont(ofSize: 11)
        theme.paint(caption) { $0.textColor = $1.color(.textTertiary) }
        let pane = NSView()
        for view in [caption, editor] + [control].compactMap({ $0 }) {
            view.translatesAutoresizingMaskIntoConstraints = false
            pane.addSubview(view)
        }
        NSLayoutConstraint.activate([
            caption.centerYAnchor.constraint(equalTo: pane.topAnchor, constant: 12),
            caption.leadingAnchor.constraint(equalTo: pane.leadingAnchor),
            editor.topAnchor.constraint(equalTo: pane.topAnchor, constant: 28),
            editor.leadingAnchor.constraint(equalTo: pane.leadingAnchor),
            editor.trailingAnchor.constraint(equalTo: pane.trailingAnchor),
            editor.bottomAnchor.constraint(equalTo: pane.bottomAnchor),
        ])
        if let control {
            NSLayoutConstraint.activate([
                control.topAnchor.constraint(equalTo: pane.topAnchor),
                control.trailingAnchor.constraint(equalTo: pane.trailingAnchor),
                control.leadingAnchor.constraint(greaterThanOrEqualTo: caption.trailingAnchor, constant: 8),
            ])
        }
        return pane
    }

    // MARK: Dropdowns

    private static let types: [(String, BodyType?)] = [("none", BodyType.none), ("raw", nil), ("form-urlencoded", .formURLEncoded),
                                                       ("multipart", .multipart), ("GraphQL", .graphql)]
    private static let kinds: [(String, RawKind)] = [("JSON", .json), ("text", .text), ("XML", .xml)]

    private static func title(_ type: BodyType) -> String {
        switch type {
        case .none: "none"
        case .raw: "raw"
        case .formURLEncoded: "form-urlencoded"
        case .multipart: "multipart"
        case .graphql: "GraphQL"
        }
    }

    private static func title(_ kind: RawKind) -> String { kinds.first { $0.1 == kind }?.0 ?? "" }

    /// raw keeps the current kind when it is raw already, and starts as JSON otherwise.
    private func pickType(_ pick: DropdownPick) {
        guard case let .option(id) = pick, let entry = Self.types.first(where: { $0.0 == id }) else { return }
        self.pick(entry.1 ?? .raw(currentKind))
    }

    private func pickKind(_ pick: DropdownPick) {
        guard case let .option(id) = pick, let kind = Self.kinds.first(where: { $0.0 == id })?.1 else { return }
        self.pick(.raw(kind))
    }

    private var currentKind: RawKind { if case .raw(let kind, _) = model.tab.definition.body { kind } else { .json } }

    /// Body, headers and, for GraphQL, the method change, so one undo puts them all back:
    /// switching to none keeps nothing, but the old body is in undo (editing.md).
    private func pick(_ type: BodyType) {
        let before = (model.tab.definition.body, model.tab.definition.headers)
        let method = model.tab.definition.method
        model.pickBodyType(type)
        showFormatError(nil)
        // Only a GraphQL pick can change the method, so any other pick leaves a hand-set one alone in undo.
        registerUndo(restoring: before, method: type == .graphql ? method : nil, name: "Body Type")
    }

    /// `method` is nil for a change that leaves the method alone, such as Format.
    private func registerUndo(restoring state: (body: Body, headers: [Row]), method: String? = nil, name: String) {
        undoManager?.registerUndo(withTarget: self) { pane in
            let now = (pane.model.tab.definition.body, pane.model.tab.definition.headers)
            let nowMethod = method == nil ? nil : pane.model.tab.definition.method
            pane.model.tab.definition.body = state.body
            pane.model.tab.definition.headers = state.headers
            if let method { pane.model.tab.definition.method = method }
            pane.registerUndo(restoring: now, method: nowMethod, name: name)
        }
        undoManager?.setActionName(name)
    }

    /// Whitespace only (editing.md §Format the body). A body that does not parse is left as it
    /// is, and the line under the editor says where it stopped. In a GraphQL body it acts on the
    /// Variables; the Query has no formatter.
    @objc private func format() {
        switch model.tab.definition.body {
        case .raw(let kind, let text) where kind != .text:
            formatText(text, as: kind) { .raw(kind, $0) }
        case .graphql(let body) where !body.variables.allSatisfy(\.isWhitespace):
            formatText(body.variables, as: .json) { formatted in
                var body = body
                body.variables = formatted
                return .graphql(body)
            }
        default:
            return
        }
    }

    private func formatText(_ text: String, as kind: RawKind, replacing write: (String) -> Body) {
        do throws(FormatError) {
            let formatted = try BodyFormatter.format(text, kind: kind)
            showFormatError(nil)
            guard formatted != text else { return }
            let before = (model.tab.definition.body, model.tab.definition.headers)
            model.tab.definition.body = write(formatted)
            registerUndo(restoring: before, name: "Format")
        } catch {
            switch error {
            case .notValid(let line, let column):
                showFormatError("Couldn't format: not valid \(Self.title(kind)) at line \(line), column \(column).")
            }
        }
    }

    private func showFormatError(_ text: String?) {
        formatError.stringValue = text ?? ""
        formatError.isHidden = text == nil
        for bottom in [boxBottom, splitBottom] { bottom.constant = text == nil ? 0 : -20 }
    }

    // MARK: Render

    /// The RequestEditor's render draws the new Tab's body.
    func bind(_ model: TabModel) {
        // The field would keep the old Tab's text and write it into this one on the next keystroke.
        if self.model !== model, operationField.currentEditor() != nil { operationField.abortEditing() }
        self.model = model
        showFormatError(nil)
    }

    func setBody(_ body: Body, kinds: VariableKinds) {
        formTable.setKinds(kinds)
        partsTable.setKinds(kinds)
        operationField.kinds = kinds
        typeDropdown.entries = Self.types.map { .option(id: $0.0, title: $0.0, detail: nil, isChosen: $0.0 == Self.title(body.type)) }
        typeWidth.constant = typeDropdown.fittingWidth
        // Each view gets its final state once. Hiding the editor box and showing it again on every
        // keystroke takes first responder away from the text view inside it.
        let rawKind: RawKind? = if case .raw(let kind, _) = body { kind } else { nil }
        let isGraphQL = body.type == .graphql
        noneNote.isHidden = body != .none
        kindDropdown.entries = Self.kinds.map { .option(id: $0.0, title: $0.0, detail: nil, isChosen: $0.1 == rawKind) }
        kindWidth.constant = kindDropdown.fittingWidth
        kindDropdown.isHidden = rawKind == nil
        formatButton.isHidden = rawKind == nil || rawKind == .text
        // Exactly one Format button shows and owns ⇧⌥F. Uppercase: with Shift held, the event's
        // charactersIgnoringModifiers is "F".
        formatButton.keyEquivalent = isGraphQL ? "" : "F"
        variablesFormatButton.keyEquivalent = isGraphQL ? "F" : ""
        rawEditor.isHidden = rawKind == nil
        for view in [operationLabel, operationBox, graphqlSplit] { view.isHidden = !isGraphQL }
        formTable.isHidden = body.type != .formURLEncoded
        partsTable.isHidden = body.type != .multipart
        // A hidden editor is not coloured, so a new Flavor does not recolour a body that is not shown.
        if rawKind == nil { rawEditor.syntax = nil }
        if !isGraphQL { queryEditor.syntax = nil; variablesEditor.syntax = nil }
        switch body {
        case .none:
            break
        case .multipart(let parts):
            partsTable.setParts(parts)
            partsTable.missingFile = model.missingFile
        case .raw(let kind, let text):
            formatButton.toolTip = "Format \(Self.title(kind)) (⇧⌥F)"
            rawEditor.show(text, syntax: .raw(kind), kinds: kinds)
        case .formURLEncoded(let rows):
            formTable.setRows(rows)
        case .graphql(let graphql):
            // Never rewrite a field under the user's typing: the cursor would jump.
            if operationField.currentEditor() == nil {
                operationField.stringValue = graphql.operationName
                operationField.highlight()
            }
            queryEditor.show(graphql.query, syntax: .graphql, kinds: kinds)
            variablesEditor.show(graphql.variables, syntax: .raw(.json), kinds: kinds)
        }
    }

    func controlTextDidChange(_ notification: Notification) {
        guard let field = notification.object as? NSTextField, field === operationField else { return }
        editGraphQL { $0.operationName = field.stringValue }
    }
}

/// Where the Query | Variables divider starts and how far it may go (design-system.md §6).
enum GraphQLSplitLayout {
    static let minimum: CGFloat = 240
    /// The gap between the editors is the divider: 8 pt either side of the grip.
    static let gap: CGFloat = 16

    /// A side keeps 240 pt; in a pane narrower than two of them it keeps half the room, so no
    /// size is negative and the sides never cross.
    static func minimum(width: CGFloat, divider: CGFloat) -> CGFloat {
        max(0, min(minimum, (width - divider) / 2))
    }

    /// The Query's width on the first layout: equal halves, the odd point going to Variables.
    /// nil while the pane has no room: not placed yet.
    static func firstPosition(width: CGFloat, divider: CGFloat) -> CGFloat? {
        let room = width - divider
        return room > 0 ? (room / 2).rounded(.down) : nil
    }
}

/// The Query beside the Variables, split 50 : 50 by a draggable 16 pt gap that draws only an upright grip.
final class GraphQLSplitView: NSSplitView, NSSplitViewDelegate {
    private let theme: ThemeEnvironment
    private var isPlaced = false

    override var dividerThickness: CGFloat { GraphQLSplitLayout.gap }

    init(theme: ThemeEnvironment) {
        self.theme = theme
        super.init(frame: .zero)
        isVertical = true
        dividerStyle = .thin
        delegate = self
        theme.paint(self) { split, _ in split.needsDisplay = true }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// The first layout with room sets 50 : 50; after that the pointer decides.
    override func layout() {
        super.layout()
        guard !isPlaced, let position = GraphQLSplitLayout.firstPosition(width: bounds.width, divider: dividerThickness) else { return }
        isPlaced = true
        setPosition(position, ofDividerAt: 0)
    }

    /// No rule, the editors have borders: the split handle's grip (EditorSplitView), upright, in `border`.
    override func drawDivider(in rect: NSRect) {
        theme.color(.border).setFill()
        NSBezierPath(roundedRect: NSRect(x: rect.midX - 1.5, y: rect.midY - 16, width: 3, height: 32), xRadius: 1.5, yRadius: 1.5).fill()
    }

    func splitView(_ splitView: NSSplitView, canCollapseSubview subview: NSView) -> Bool { false }

    func splitView(_ splitView: NSSplitView, constrainMinCoordinate proposed: CGFloat, ofSubviewAt index: Int) -> CGFloat {
        proposed + GraphQLSplitLayout.minimum(width: bounds.width, divider: dividerThickness)
    }

    func splitView(_ splitView: NSSplitView, constrainMaxCoordinate proposed: CGFloat, ofSubviewAt index: Int) -> CGFloat {
        proposed - GraphQLSplitLayout.minimum(width: bounds.width, divider: dividerThickness)
    }
}

/// A bordered button with 10 pt either side of its title.
final class PopButton: NSButton {
    override var intrinsicContentSize: NSSize {
        NSSize(width: attributedTitle.size().width.rounded(.up) + 20, height: 24)
    }
}

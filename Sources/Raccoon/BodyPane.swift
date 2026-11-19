import AppKit
import RaccoonDomain

/// The Body section: the Body Type pop-up, the raw kind pop-up, then "no body", the raw text
/// editor, the form table, the multipart table or the GraphQL Query and Variables editors
/// (design-system.md §6 Body editor).
final class BodyPane: NSView, NSTextFieldDelegate {
    private var model: TabModel
    private let theme: ThemeEnvironment
    let typeButton = PopButton()
    let kindButton = PopButton()
    let noneNote = NSTextField(labelWithString: "This request has no body.")
    /// Raw JSON and XML, and the GraphQL Variables; manual, never on paste or save (Open UI question 15).
    let formatButton = PopButton()
    /// "Couldn't format: …" under the editor until the next edit.
    let formatError = NSTextField(labelWithString: "")
    /// The raw body's editor.
    private let rawEditor: BodyTextEditor
    var textView: NSTextView { rawEditor.textView }
    /// `background` with a 1 pt `border` and a 6 pt radius around the editor and its line numbers.
    var textBox: NSView { rawEditor }
    /// The GraphQL body: Operation Name on the Body Type row, Query over Variables below it.
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
        // Format acts on Variables only, so it is enabled while Variables has focus.
        variablesEditor.onFocus = { [weak self] focused in
            // A hidden Variables editor can report losing focus after the body changed; raw Format stays as it was.
            guard let self, case .graphql = model.tab.definition.body else { return }
            setFormatEnabled(focused)
        }
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

    private func setFormatEnabled(_ enabled: Bool) {
        formatButton.isEnabled = enabled
        formatButton.alphaValue = enabled ? 1 : 0.4
    }

    // MARK: Layout

    private func buildControls() {
        let label = NSTextField(labelWithString: "Body Type")
        label.font = .systemFont(ofSize: 11)
        theme.paint(label) { $0.textColor = $1.color(.textTertiary) }
        for (button, action) in [(typeButton, #selector(showTypes)), (kindButton, #selector(showKinds))] {
            button.isBordered = false
            button.wantsLayer = true
            button.layer?.cornerRadius = 6
            button.layer?.borderWidth = 1
            theme.paint(button) { button, theme in
                button.layer?.borderColor = theme.color(.border).cgColor
                button.layer?.backgroundColor = theme.color(.backgroundElevated).cgColor
            }
            button.target = self
            button.action = action
            button.setAccessibilityRole(.popUpButton)
            button.translatesAutoresizingMaskIntoConstraints = false
            button.heightAnchor.constraint(equalToConstant: 24).isActive = true
        }
        typeButton.setAccessibilityLabel("Body Type")
        kindButton.setAccessibilityLabel("Raw kind")
        noneNote.font = .systemFont(ofSize: 12)
        theme.paint(noneNote) { $0.textColor = $1.color(.textTertiary) }

        formatButton.isBordered = false
        formatButton.wantsLayer = true
        formatButton.layer?.cornerRadius = 6
        formatButton.layer?.borderWidth = 1
        theme.paint(formatButton) { button, theme in
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
        formatButton.setAccessibilityLabel("Format")
        formatButton.target = self
        formatButton.action = #selector(format)
        // Uppercase: with Shift held, the event's charactersIgnoringModifiers is "F".
        formatButton.keyEquivalent = "F"
        formatButton.keyEquivalentModifierMask = [.shift, .option]
        formatButton.refusesFirstResponder = true
        formatError.font = .systemFont(ofSize: 11)
        theme.paint(formatError) { $0.textColor = $1.color(.error) }
        formatError.isHidden = true

        buildOperationName()
        let spacer = NSView()
        spacer.setContentHuggingPriority(.init(1), for: .horizontal)
        let row = NSStackView(views: [label, typeButton, kindButton, operationLabel, operationBox, spacer, formatButton])
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
        graphqlSplit.addArrangedSubview(captioned("Query", queryEditor, top: 0, bottom: 8))
        graphqlSplit.addArrangedSubview(captioned("Variables", variablesEditor, top: 8, bottom: 0))
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

    /// An 11 pt `textTertiary` caption over an editor.
    private func captioned(_ title: String, _ editor: BodyTextEditor, top: CGFloat, bottom: CGFloat) -> NSView {
        let caption = NSTextField(labelWithString: title)
        caption.font = .systemFont(ofSize: 11)
        theme.paint(caption) { $0.textColor = $1.color(.textTertiary) }
        let pane = NSView()
        for view in [caption, editor] {
            view.translatesAutoresizingMaskIntoConstraints = false
            pane.addSubview(view)
        }
        NSLayoutConstraint.activate([
            caption.topAnchor.constraint(equalTo: pane.topAnchor, constant: top),
            caption.leadingAnchor.constraint(equalTo: pane.leadingAnchor),
            editor.topAnchor.constraint(equalTo: caption.bottomAnchor, constant: 4),
            editor.leadingAnchor.constraint(equalTo: pane.leadingAnchor),
            editor.trailingAnchor.constraint(equalTo: pane.trailingAnchor),
            editor.bottomAnchor.constraint(equalTo: pane.bottomAnchor, constant: -bottom),
        ])
        return pane
    }

    private func popTitle(_ text: String) -> NSAttributedString {
        let title = NSMutableAttributedString(string: text, attributes: [
            .font: NSFont.systemFont(ofSize: 12), .foregroundColor: theme.color(.text),
        ])
        title.append(NSAttributedString(string: "  ⌄", attributes: [
            .font: NSFont.systemFont(ofSize: 10), .foregroundColor: theme.color(.textTertiary), .baselineOffset: 2,
        ]))
        return title
    }

    // MARK: Menus

    private static let types: [(String, BodyType?)] = [("none", BodyType.none), ("raw", nil), ("form-urlencoded", .formURLEncoded),
                                                       ("multipart", .multipart), ("GraphQL", .graphql)]
    private static let kinds: [(String, RawKind)] = [("JSON", .json), ("text", .text), ("XML", .xml)]

    var typeMenu: NSMenu {
        menu(Self.types.map(\.0), selected: Self.title(model.tab.definition.body.type), action: #selector(pickType))
    }

    var kindMenu: NSMenu {
        let selected: String? = if case .raw(let kind, _) = model.tab.definition.body { Self.title(kind) } else { nil }
        return menu(Self.kinds.map(\.0), selected: selected, action: #selector(pickKind))
    }

    private func menu(_ titles: [String], selected: String?, action: Selector) -> NSMenu {
        let menu = NSMenu()
        for (index, title) in titles.enumerated() {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
            item.target = self
            item.tag = index
            item.state = title == selected ? .on : .off
            menu.addItem(item)
        }
        return menu
    }

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

    @objc private func showTypes() { typeMenu.popUp(positioning: nil, at: NSPoint(x: 0, y: typeButton.bounds.height + 4), in: typeButton) }
    @objc private func showKinds() { kindMenu.popUp(positioning: nil, at: NSPoint(x: 0, y: kindButton.bounds.height + 4), in: kindButton) }

    /// raw keeps the current kind when it is raw already, and starts as JSON otherwise.
    @objc private func pickType(_ item: NSMenuItem) {
        let current: RawKind = if case .raw(let kind, _) = model.tab.definition.body { kind } else { .json }
        pick(Self.types[item.tag].1 ?? .raw(current))
    }

    @objc private func pickKind(_ item: NSMenuItem) { pick(.raw(Self.kinds[item.tag].1)) }

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
        typeButton.attributedTitle = popTitle(Self.title(body.type))
        typeButton.setAccessibilityValue(Self.title(body.type))
        // Each view gets its final state once. Hiding the editor box and showing it again on every
        // keystroke takes first responder away from the text view inside it.
        let rawKind: RawKind? = if case .raw(let kind, _) = body { kind } else { nil }
        let isGraphQL = body.type == .graphql
        noneNote.isHidden = body != .none
        kindButton.isHidden = rawKind == nil
        formatButton.isHidden = !isGraphQL && (rawKind == nil || rawKind == .text)
        rawEditor.isHidden = rawKind == nil
        for view in [operationLabel, operationBox, graphqlSplit] { view.isHidden = !isGraphQL }
        formTable.isHidden = body.type != .formURLEncoded
        partsTable.isHidden = body.type != .multipart
        // A hidden editor is not coloured, so a new Flavor does not recolour a body that is not shown.
        if rawKind == nil { rawEditor.syntax = nil }
        if !isGraphQL { queryEditor.syntax = nil; variablesEditor.syntax = nil }
        let variables = variablesEditor.textView
        setFormatEnabled(!isGraphQL || variables.window?.firstResponder === variables)
        switch body {
        case .none:
            break
        case .multipart(let parts):
            partsTable.setParts(parts)
            partsTable.missingFile = model.missingFile
        case .raw(let kind, let text):
            kindButton.attributedTitle = popTitle(Self.title(kind))
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
            formatButton.toolTip = "Format JSON (⇧⌥F)"
            queryEditor.show(graphql.query, syntax: .graphql, kinds: kinds)
            variablesEditor.show(graphql.variables, syntax: .raw(.json), kinds: kinds)
        }
    }

    func controlTextDidChange(_ notification: Notification) {
        guard let field = notification.object as? NSTextField, field === operationField else { return }
        editGraphQL { $0.operationName = field.stringValue }
    }
}

/// The Query over the Variables, split 2 : 1 by a draggable 1 pt `border` divider.
final class GraphQLSplitView: NSSplitView, NSSplitViewDelegate {
    private let theme: ThemeEnvironment
    private var isPlaced = false
    private static let minimum: CGFloat = 64

    override var dividerColor: NSColor { theme.color(.border) }

    init(theme: ThemeEnvironment) {
        self.theme = theme
        super.init(frame: .zero)
        isVertical = false
        dividerStyle = .thin
        delegate = self
        theme.paint(self) { split, _ in split.needsDisplay = true }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// The first layout with a height sets 2 : 1; after that the pointer decides.
    override func layout() {
        super.layout()
        guard !isPlaced, bounds.height > 2 * Self.minimum + dividerThickness else { return }
        isPlaced = true
        setPosition((bounds.height - dividerThickness) * 2 / 3, ofDividerAt: 0)
    }

    func splitView(_ splitView: NSSplitView, canCollapseSubview subview: NSView) -> Bool { false }

    func splitView(_ splitView: NSSplitView, constrainMinCoordinate proposed: CGFloat, ofSubviewAt index: Int) -> CGFloat {
        proposed + Self.minimum
    }

    func splitView(_ splitView: NSSplitView, constrainMaxCoordinate proposed: CGFloat, ofSubviewAt index: Int) -> CGFloat {
        proposed - Self.minimum
    }
}

/// A pop-up drawn as a bordered button: 10 pt either side of its title.
final class PopButton: NSButton {
    override var intrinsicContentSize: NSSize {
        NSSize(width: attributedTitle.size().width.rounded(.up) + 20, height: 24)
    }
}

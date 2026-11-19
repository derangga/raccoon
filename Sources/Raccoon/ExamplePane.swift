import AppKit
import Observation
import RaccoonDomain

/// What the Example pane's Section bar offers.
enum ExampleSection: CaseIterable {
    case headers, body

    var name: String {
        switch self {
        case .headers: "Headers"
        case .body: "Body"
        }
    }

    /// A row count, Disabled Rows too; none for no rows, and none for Body.
    func detail(in example: Example) -> String? {
        switch self {
        case .headers: example.headers.isEmpty ? nil : "\(example.headers.count)"
        case .body: nil
        }
    }

    func title(in example: Example) -> String {
        detail(in: example).map { "\(name) \($0)" } ?? name
    }
}

/// What an Example Tab shows in place of the URL bar, the RequestEditor and the Response viewer
/// (design-system.md §6 Example pane): a header row with the name, Status and Delay, then the
/// Section bar over Headers and Body. It keeps no values of its own: the bound Tab's Example is
/// drawn, and an edit goes through the Tab's edit methods, one undo step each. One pane serves the
/// window and is bound to the selected Example Tab, as the RequestEditor is.
final class ExamplePane: NSView, NSTextFieldDelegate {
    static let headerHeight: CGFloat = 44

    private(set) var model: TabModel
    private let theme: ThemeEnvironment
    private(set) var selected = ExampleSection.body
    private var buttons: [ExampleSection: SectionButton] = [:]
    private var panes: [ExampleSection: NSView] = [:]
    /// Counts renders, so only the newest observation chain keeps drawing.
    private var renders = 0
    /// Esc ended the edit, so what was typed is thrown away.
    private var cancelled = false

    let headerRow = NSStackView()
    let nameField = NSTextField()
    let statusLabel = NSTextField(labelWithString: "Status")
    let statusField = NSTextField()
    let reasonLabel = NSTextField(labelWithString: "")
    let delayLabel = NSTextField(labelWithString: "Delay")
    let delayField = NSTextField()
    let unitLabel = NSTextField(labelWithString: "ms")
    let headersTable: KeyValueTable
    let bodyEditor: BodyTextEditor
    let hexView: ExampleHexView

    init(model: TabModel, theme: ThemeEnvironment) {
        self.model = model
        self.theme = theme
        headersTable = KeyValueTable(theme: theme)
        bodyEditor = BodyTextEditor(theme: theme)
        hexView = ExampleHexView(theme: theme)
        super.init(frame: .zero)
        wantsLayer = true
        theme.paint(self) { $0.layer?.backgroundColor = $1.color(.background).cgColor }
        headersTable.onChange = { [weak self] rows in
            guard let self else { return }
            self.model.setExampleHeaders(rows, undo: undoManager)
        }
        // An Example's body is what is served, not a template: `{{name}}` is just text.
        bodyEditor.highlightsVariables = false
        // The text view's own typing undo is the step, so no manager goes with it.
        bodyEditor.onChange = { [weak self] text in self?.model.setExampleBody(.text(text)) }
        hexView.replaceButton.target = self
        hexView.replaceButton.action = #selector(replaceFromFile)
        // No target: Save Body goes up the responder chain to the AppDelegate, as the Response viewer's does.
        hexView.saveButton.action = #selector(AppDelegate.saveResponseBody(_:))

        buildHeaderRow()
        let bar = buildSectionBar()
        let rule = NSBox()
        rule.boxType = .custom
        rule.borderWidth = 0
        theme.paint(rule) { $0.fillColor = $1.color(.border) }
        let barRule = NSBox()
        barRule.boxType = .custom
        barRule.borderWidth = 0
        theme.paint(barRule) { $0.fillColor = $1.color(.border) }
        let paneArea = buildPanes()

        for view in [headerRow, rule, bar, barRule, paneArea] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        NSLayoutConstraint.activate([
            headerRow.topAnchor.constraint(equalTo: topAnchor),
            headerRow.leadingAnchor.constraint(equalTo: leadingAnchor),
            headerRow.trailingAnchor.constraint(equalTo: trailingAnchor),
            headerRow.heightAnchor.constraint(equalToConstant: Self.headerHeight),
            rule.topAnchor.constraint(equalTo: headerRow.bottomAnchor),
            rule.leadingAnchor.constraint(equalTo: leadingAnchor),
            rule.trailingAnchor.constraint(equalTo: trailingAnchor),
            rule.heightAnchor.constraint(equalToConstant: 1),
            bar.topAnchor.constraint(equalTo: rule.bottomAnchor),
            bar.leadingAnchor.constraint(equalTo: leadingAnchor),
            bar.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor),
            bar.heightAnchor.constraint(equalToConstant: 32),
            barRule.topAnchor.constraint(equalTo: bar.bottomAnchor, constant: -1),
            barRule.leadingAnchor.constraint(equalTo: leadingAnchor),
            barRule.trailingAnchor.constraint(equalTo: trailingAnchor),
            barRule.heightAnchor.constraint(equalToConstant: 1),
            paneArea.topAnchor.constraint(equalTo: barRule.bottomAnchor),
            paneArea.leadingAnchor.constraint(equalTo: leadingAnchor),
            paneArea.trailingAnchor.constraint(equalTo: trailingAnchor),
            paneArea.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        // The bar sits above its rule, so the selected underline covers it.
        addSubview(bar, positioned: .above, relativeTo: barRule)
        select(.body)
        render()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    // MARK: Layout

    private func buildHeaderRow() {
        nameField.placeholderString = "Name"
        nameField.setAccessibilityLabel("Example name")
        nameField.font = .systemFont(ofSize: 13)
        nameField.setContentHuggingPriority(.init(1), for: .horizontal)
        nameField.widthAnchor.constraint(greaterThanOrEqualToConstant: 120).isActive = true
        for (field, label) in [(statusField, "Status"), (delayField, "Delay in milliseconds")] {
            field.alignment = .right
            field.font = .monospacedDigitSystemFont(ofSize: 13, weight: .regular)
            field.setAccessibilityLabel(label)
            field.widthAnchor.constraint(equalToConstant: 64).isActive = true
        }
        for field in [nameField, statusField, delayField] { field.delegate = self }
        for label in [statusLabel, delayLabel, unitLabel] {
            label.font = .systemFont(ofSize: 12)
            theme.paint(label) { $0.textColor = $1.color(.textTertiary) }
        }
        reasonLabel.font = .systemFont(ofSize: 12)
        reasonLabel.lineBreakMode = .byTruncatingTail
        // The reason is what gives way at a narrow width.
        reasonLabel.setContentCompressionResistancePriority(.init(1), for: .horizontal)
        theme.paint(reasonLabel) { $0.textColor = $1.color(.textTertiary) }
        for view in [statusLabel, statusField, delayLabel, delayField, unitLabel] {
            view.setContentCompressionResistancePriority(.required, for: .horizontal)
        }

        for view in [nameField, statusLabel, statusField, reasonLabel, delayLabel, delayField, unitLabel] { headerRow.addArrangedSubview(view) }
        headerRow.orientation = .horizontal
        headerRow.alignment = .centerY
        // The name takes the slack; with gravity areas the row ends short of its trailing inset.
        headerRow.distribution = .fill
        headerRow.spacing = 8
        headerRow.setCustomSpacing(16, after: nameField)
        headerRow.setCustomSpacing(16, after: reasonLabel)
        headerRow.edgeInsets = NSEdgeInsets(top: 0, left: 12, bottom: 0, right: 12)
    }

    private func buildSectionBar() -> NSStackView {
        let bar = NSStackView()
        bar.spacing = 2
        bar.edgeInsets = NSEdgeInsets(top: 4, left: 12, bottom: 0, right: 12)
        bar.alignment = .bottom
        bar.setAccessibilityRole(.tabGroup)
        bar.setAccessibilityLabel("Example sections")
        for section in ExampleSection.allCases {
            let button = SectionButton(theme: theme, target: self, action: #selector(sectionClicked))
            buttons[section] = button
            bar.addArrangedSubview(button)
        }
        return bar
    }

    private func buildPanes() -> NSView {
        let paneArea = NSView()
        let bodyPane = NSView()
        for view in [bodyEditor, hexView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            bodyPane.addSubview(view)
            NSLayoutConstraint.activate([
                view.topAnchor.constraint(equalTo: bodyPane.topAnchor),
                view.leadingAnchor.constraint(equalTo: bodyPane.leadingAnchor),
                view.trailingAnchor.constraint(equalTo: bodyPane.trailingAnchor),
                view.bottomAnchor.constraint(equalTo: bodyPane.bottomAnchor),
            ])
        }
        panes = [.headers: headersTable, .body: bodyPane]
        for pane in panes.values {
            pane.translatesAutoresizingMaskIntoConstraints = false
            paneArea.addSubview(pane)
            NSLayoutConstraint.activate([
                pane.leadingAnchor.constraint(equalTo: paneArea.leadingAnchor, constant: 12),
                pane.trailingAnchor.constraint(equalTo: paneArea.trailingAnchor, constant: -12),
                pane.topAnchor.constraint(equalTo: paneArea.topAnchor, constant: 8),
                pane.bottomAnchor.constraint(lessThanOrEqualTo: paneArea.bottomAnchor, constant: -8),
            ])
            // A table hugs its rows; the body fills the area.
            if pane === bodyPane { pane.bottomAnchor.constraint(equalTo: paneArea.bottomAnchor, constant: -8).isActive = true }
            pane.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        }
        return paneArea
    }

    func sectionButton(_ section: ExampleSection) -> SectionButton {
        guard let button = buttons[section] else { preconditionFailure("every section has a button") }
        return button
    }

    func select(_ section: ExampleSection) {
        selected = section
        for (each, pane) in panes { pane.isHidden = each != section }
        for (each, button) in buttons { button.isOn = each == section }
    }

    @objc private func sectionClicked(_ sender: SectionButton) {
        guard let section = buttons.first(where: { $0.value === sender })?.key else { return }
        select(section)
    }

    // MARK: Tabs

    /// Shows another Example Tab, keeping where the old one was. The undo stack is the window's, and
    /// its actions read whichever Tab is bound, so a switch drops them.
    func bind(_ model: TabModel) {
        guard model !== self.model else { return }
        // A field being edited writes its text to the Tab it was typed in.
        if let window, let focused = window.firstResponder as? NSView, focused.isDescendant(of: self) {
            window.makeFirstResponder(nil)
        }
        self.model.viewState.exampleSection = selected
        self.model.viewState.body = bodyEditor.textView.place
        undoManager?.removeAllActions()
        self.model = model
        hexView.setError(nil)
        select(model.viewState.exampleSection)
        render()
        layoutSubtreeIfNeeded()
        bodyEditor.textView.restore(model.viewState.body)
    }

    // MARK: Render

    /// Redraws from the Tab's Example, and again whenever it changes, while it is still the bound one.
    func render() {
        renders += 1
        let mine = renders
        withObservationTracking {
            guard let example = model.tab.example else { return }
            draw(example)
        } onChange: { [weak self] in
            Task { @MainActor in if self?.renders == mine { self?.render() } }
        }
    }

    private func draw(_ example: Example) {
        // A field being typed in keeps its text: a redraw must not fight the caret.
        for (field, text) in [(nameField, example.name), (statusField, "\(example.status)"), (delayField, "\(example.delayMilliseconds)")]
        where field.currentEditor() == nil {
            field.stringValue = text
        }
        reasonLabel.stringValue = StatusLine(status: example.status, elapsed: .zero, byteCount: 0).reason
        for (section, button) in buttons { button.set(name: section.name, detail: section.detail(in: example)) }
        headersTable.setRows(example.headers)
        switch example.body {
        case .text(let text):
            hexView.isHidden = true
            bodyEditor.isHidden = false
            bodyEditor.show(text, syntax: .raw(example.bodySyntax), kinds: VariableKinds(active: nil, globals: Globals(entries: [])))
        case .bytes(let data):
            bodyEditor.isHidden = true
            hexView.isHidden = false
            hexView.show(data)
        }
    }

    // MARK: Fields

    /// A number as typed: nothing readable keeps what was there, and more digits than an Int holds is
    /// the top of the range. The Example clamps the rest.
    static func number(_ text: String, keeping current: Int) -> Int {
        let digits = text.trimmingCharacters(in: .whitespaces)
        return Int(digits) ?? (!digits.isEmpty && digits.allSatisfy(\.isNumber) ? .max : current)
    }

    /// Return, Tab and a click elsewhere commit, and so does ⌘S, which ends the edit first. The fields
    /// then show what the Example kept, so a clamp is visible.
    func controlTextDidEndEditing(_ notification: Notification) {
        guard let field = notification.object as? NSTextField, let example = model.tab.example else { return }
        if cancelled {
            cancelled = false
        } else if field === nameField {
            model.setExampleName(field.stringValue, undo: undoManager)
        } else if field === statusField {
            model.setExampleStatus(Self.number(field.stringValue, keeping: example.status), undo: undoManager)
        } else if field === delayField {
            model.setExampleDelay(Self.number(field.stringValue, keeping: example.delayMilliseconds), undo: undoManager)
        }
        guard let kept = model.tab.example else { return }
        // Written straight to the field: its editor may outlive this call, and a redraw leaves such a field alone.
        nameField.stringValue = kept.name
        statusField.stringValue = "\(kept.status)"
        delayField.stringValue = "\(kept.delayMilliseconds)"
        reasonLabel.stringValue = StatusLine(status: kept.status, elapsed: .zero, byteCount: 0).reason
    }

    /// Esc gives focus up and leaves the Example as it was, as a value field in the Settings does.
    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        guard selector == #selector(NSResponder.cancelOperation(_:)) else { return false }
        cancelled = true
        window?.makeFirstResponder(nil)
        return true
    }

    // MARK: Replace from File…

    @objc private func replaceFromFile() {
        guard let window, window.attachedSheet == nil else { return }
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        let bound = model
        Task { @MainActor [weak self] in
            guard await panel.beginSheetModal(for: window) == .OK, let url = panel.url, let self, model === bound else { return }
            replace(fromFile: url.path)
        }
    }

    /// The file's bytes become the body, by the Response's UTF-8 rule. A file that does not read
    /// changes nothing, and the toolbar says why until the next replace.
    func replace(fromFile path: String) {
        do throws(StoreError) {
            try model.replaceExampleBody(fromFile: path, undo: undoManager)
            hexView.setError(nil)
        } catch {
            switch error {
            case .unreadable(_, let reason), .unwritable(_, let reason), .undecodable(_, let reason):
                hexView.setError("Couldn't replace the body: \(reason).")
            }
        }
    }
}

/// The Hex view of a `.bytes` body, read-only, under a Body toolbar with Replace from File… and
/// Save Body… (design-system.md §6 Example pane): a bordered box like the body editor.
final class ExampleHexView: NSView {
    static let toolbarHeight: CGFloat = 38

    private let theme: ThemeEnvironment
    let toolbar = NSView()
    let replaceButton = NSButton()
    let saveButton = NSButton()
    /// "Showing the first 1 MB of 3.2 MB", above the Hex view's limit.
    let limitNote = NSTextField(labelWithString: "")
    /// "Couldn't replace the body: …", in `error`.
    let errorNote = NSTextField(labelWithString: "")
    let textView: NSTextView
    private let scroll = NSScrollView()
    private var shown: Data?

    init(theme: ThemeEnvironment) {
        self.theme = theme
        // TextKit 1, as the Response body (environment-facts.md).
        textView = NSTextView(usingTextLayoutManager: false)
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 6
        layer?.borderWidth = 1
        layer?.masksToBounds = true
        theme.paint(self) { view, theme in
            view.layer?.borderColor = theme.color(.border).cgColor
            view.layer?.backgroundColor = theme.color(.background).cgColor
            view.textView.textColor = theme.color(.text)
        }
        build()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    private func build() {
        FixButton.style(replaceButton, title: "Replace from File…", theme: theme)
        FixButton.style(saveButton, title: "Save Body…", theme: theme)
        for note in [limitNote, errorNote] {
            note.font = .systemFont(ofSize: 11)
            note.lineBreakMode = .byTruncatingTail
            // The note is what gives way at a narrow width.
            note.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            note.isHidden = true
        }
        theme.paint(limitNote) { $0.textColor = $1.color(.textDisabled) }
        theme.paint(errorNote) { $0.textColor = $1.color(.error) }

        let spacer = NSView()
        spacer.setContentHuggingPriority(.init(1), for: .horizontal)
        let row = NSStackView(views: [replaceButton, saveButton, limitNote, errorNote, spacer])
        row.spacing = 10
        row.edgeInsets = NSEdgeInsets(top: 0, left: 12, bottom: 0, right: 12)
        let rule = NSBox()
        rule.boxType = .custom
        rule.borderWidth = 0
        theme.paint(rule) { $0.fillColor = $1.color(.border) }

        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        textView.textContainerInset = NSSize(width: 8, height: 8)
        // The dump never wraps: the view grows sideways and scrolls.
        textView.textContainer?.widthTracksTextView = false
        textView.textContainer?.size = NSSize(width: CGFloat.greatestFiniteMagnitude, height: .greatestFiniteMagnitude)
        textView.isHorizontallyResizable = true
        textView.isVerticallyResizable = true
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: .greatestFiniteMagnitude)
        textView.autoresizingMask = []
        scroll.documentView = textView
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false

        for view in [toolbar, row, rule, scroll] { view.translatesAutoresizingMaskIntoConstraints = false }
        toolbar.addSubview(row)
        addSubview(toolbar)
        addSubview(rule)
        addSubview(scroll)
        NSLayoutConstraint.activate([
            toolbar.topAnchor.constraint(equalTo: topAnchor, constant: 1),
            toolbar.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 1),
            toolbar.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -1),
            toolbar.heightAnchor.constraint(equalToConstant: Self.toolbarHeight),
            row.topAnchor.constraint(equalTo: toolbar.topAnchor),
            row.bottomAnchor.constraint(equalTo: toolbar.bottomAnchor),
            row.leadingAnchor.constraint(equalTo: toolbar.leadingAnchor),
            row.trailingAnchor.constraint(equalTo: toolbar.trailingAnchor),
            rule.topAnchor.constraint(equalTo: toolbar.bottomAnchor),
            rule.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 1),
            rule.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -1),
            rule.heightAnchor.constraint(equalToConstant: 1),
            scroll.topAnchor.constraint(equalTo: rule.bottomAnchor),
            scroll.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 1),
            scroll.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -1),
            scroll.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -1),
        ])
    }

    /// The dump of `data`, made again only for other bytes.
    func show(_ data: Data) {
        guard data != shown else { return }
        shown = data
        let hex = HexDump(data)
        textView.string = hex.text
        textView.scrollToBeginningOfDocument(nil)
        limitNote.isHidden = hex.totalBytes <= hex.shownBytes
        if !limitNote.isHidden {
            let size = StatusLine(status: 0, elapsed: .zero, byteCount: hex.totalBytes).size
            limitNote.stringValue = "Showing the first \(HexDump.limit / 1_000_000) MB of \(size)"
        }
    }

    func setError(_ text: String?) {
        errorNote.stringValue = text ?? ""
        errorNote.isHidden = text == nil
    }
}

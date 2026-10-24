import AppKit
import RaccoonDomain

/// The Body section: the Body Type pop-up, the raw kind pop-up, then "no body", the raw text
/// editor, the form table or the multipart table (design-system.md §6 Body editor).
final class BodyPane: NSView, NSTextViewDelegate {
    private var model: TabModel
    private let theme: ThemeEnvironment
    let typeButton = PopButton()
    let kindButton = PopButton()
    let noneNote = NSTextField(labelWithString: "This request has no body.")
    /// Raw JSON and XML only; manual, never on paste or save (Open UI question 15).
    let formatButton = PopButton()
    /// "Couldn't format: …" under the editor until the next edit.
    let formatError = NSTextField(labelWithString: "")
    let textView: NSTextView
    /// `background` with a 1 pt `border` and a 6 pt radius around the editor and its line numbers.
    let textBox = NSView()
    private let scroll = NSScrollView()
    private lazy var gutter: Gutter = {
        let gutter = Gutter(textView: textView, theme: theme)
        gutter.lines = LineIndex("")
        return gutter
    }()
    private let layoutManager = WavyLayoutManager()
    /// The layout manager does not retain its storage, so the view must.
    private var storage = NSTextStorage()
    let formTable: KeyValueTable
    let partsTable: KeyValueTable
    private var font: NSFont { .monospacedSystemFont(ofSize: 12, weight: .regular) }
    private var boxBottom = NSLayoutConstraint()
    /// The kind the storage is colored for, so a kind change recolors without new text.
    private var coloredKind: RawKind?
    /// The Variables the storage is coloured by; a new Active Environment recolours it.
    private var kinds = VariableKinds(active: nil, globals: Globals(entries: []))
    private var coloredKinds: VariableKinds?

    init(model: TabModel, theme: ThemeEnvironment) {
        self.model = model
        self.theme = theme
        formTable = KeyValueTable(theme: theme)
        partsTable = KeyValueTable(theme: theme, allowsFiles: true)
        // TextKit 1 with non-contiguous layout, as the Response body (environment-facts.md).
        let container = NSTextContainer(size: NSSize(width: CGFloat.greatestFiniteMagnitude, height: .greatestFiniteMagnitude))
        container.widthTracksTextView = false
        layoutManager.allowsNonContiguousLayout = true
        layoutManager.addTextContainer(container)
        storage.addLayoutManager(layoutManager)
        textView = HoverTextView(frame: .zero, textContainer: container)
        super.init(frame: .zero)
        (textView as? HoverTextView)?.variableHover = VariableHover(
            layout: { [weak self] in self.map { TextLayout(storage: $0.storage, manager: $0.layoutManager, origin: $0.textView.textContainerOrigin, space: $0.textView) } },
            kinds: { [weak self] in self?.kinds }, theme: { [weak self] in self?.theme }
        )
        (textView as? HoverTextView)?.suggestions = VariableSuggestions(kinds: { [weak self] in self?.kinds }, theme: { [weak self] in self?.theme })
        formTable.onChange = { [weak self] in self?.model.tab.definition.body = .formURLEncoded($0) }
        partsTable.onChange = { [weak self] rows in
            guard let self else { return }
            model.tab.definition.body = .multipart(partsTable.parts(rows))
        }
        buildControls()
        buildEditor()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

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
        formatError.font = .systemFont(ofSize: 11)
        theme.paint(formatError) { $0.textColor = $1.color(.error) }
        formatError.isHidden = true

        let spacer = NSView()
        spacer.setContentHuggingPriority(.init(1), for: .horizontal)
        let row = NSStackView(views: [label, typeButton, kindButton, spacer, formatButton])
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

    private func buildEditor() {
        textView.delegate = self
        textView.isRichText = false
        textView.allowsUndo = true
        textView.drawsBackground = false
        textView.font = font
        // The storage keeps the colours of the last pass, so a new Flavor recolours it.
        theme.paint(self) { pane, theme in
            pane.textView.textColor = theme.color(.text)
            pane.textView.insertionPointColor = theme.color(.text)
            pane.textView.typingAttributes = [.font: pane.font, .foregroundColor: theme.color(.text)]
            if let kind = pane.coloredKind { pane.color(pane.storage, kind: kind) }
        }
        for substitution in [\NSTextView.isAutomaticQuoteSubstitutionEnabled, \.isAutomaticDashSubstitutionEnabled,
                             \.isAutomaticTextReplacementEnabled, \.isAutomaticSpellingCorrectionEnabled] {
            textView[keyPath: substitution] = false
        }
        textView.textContainerInset = NSSize(width: 4, height: 8)
        // Bodies never wrap: the view grows sideways and scrolls.
        textView.isHorizontallyResizable = true
        textView.isVerticallyResizable = true
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: .greatestFiniteMagnitude)
        textView.autoresizingMask = []
        scroll.documentView = textView
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false
        scroll.verticalRulerView = gutter
        scroll.hasVerticalRuler = true
        scroll.rulersVisible = true

        textBox.wantsLayer = true
        textBox.layer?.cornerRadius = 6
        textBox.layer?.borderWidth = 1
        theme.paint(textBox) { box, theme in
            box.layer?.borderColor = theme.color(.border).cgColor
            box.layer?.backgroundColor = theme.color(.background).cgColor
        }
        textBox.layer?.masksToBounds = true
        for (view, parent) in [(textBox, self as NSView), (scroll, textBox), (formatError, self)] {
            view.translatesAutoresizingMaskIntoConstraints = false
            parent.addSubview(view)
        }
        // The error line takes 20 pt from the bottom of the box only while it shows.
        boxBottom = textBox.bottomAnchor.constraint(equalTo: bottomAnchor)
        NSLayoutConstraint.activate([
            textBox.topAnchor.constraint(equalTo: topAnchor, constant: 34),
            textBox.leadingAnchor.constraint(equalTo: leadingAnchor),
            textBox.trailingAnchor.constraint(equalTo: trailingAnchor),
            boxBottom,
            formatError.leadingAnchor.constraint(equalTo: leadingAnchor),
            formatError.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor),
            formatError.bottomAnchor.constraint(equalTo: bottomAnchor),
            scroll.topAnchor.constraint(equalTo: textBox.topAnchor, constant: 1),
            scroll.leadingAnchor.constraint(equalTo: textBox.leadingAnchor, constant: 1),
            scroll.trailingAnchor.constraint(equalTo: textBox.trailingAnchor, constant: -1),
            scroll.bottomAnchor.constraint(equalTo: textBox.bottomAnchor, constant: -1),
        ])
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
                                                       ("multipart", .multipart)]
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

    /// Body and headers both change, so one undo puts both back: switching to none keeps
    /// nothing, but the old body is in undo (editing.md).
    private func pick(_ type: BodyType) {
        let before = (model.tab.definition.body, model.tab.definition.headers)
        model.pickBodyType(type)
        showFormatError(nil)
        registerUndo(restoring: before, name: "Body Type")
    }

    private func registerUndo(restoring state: (body: Body, headers: [Row]), name: String) {
        undoManager?.registerUndo(withTarget: self) { pane in
            let now = (pane.model.tab.definition.body, pane.model.tab.definition.headers)
            pane.model.tab.definition.body = state.body
            pane.model.tab.definition.headers = state.headers
            pane.registerUndo(restoring: now, name: name)
        }
        undoManager?.setActionName(name)
    }

    /// Whitespace only (editing.md §Format the body). A body that does not parse is left as it
    /// is, and the line under the editor says where it stopped.
    @objc private func format() {
        guard case .raw(let kind, let text) = model.tab.definition.body, kind != .text else { return }
        do throws(FormatError) {
            let formatted = try BodyFormatter.format(text, kind: kind)
            showFormatError(nil)
            guard formatted != text else { return }
            let before = (model.tab.definition.body, model.tab.definition.headers)
            model.tab.definition.body = .raw(kind, formatted)
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
        boxBottom.constant = text == nil ? 0 : -20
    }

    // MARK: Render

    /// The RequestEditor's render draws the new Tab's body.
    func bind(_ model: TabModel) {
        self.model = model
        showFormatError(nil)
    }

    func setBody(_ body: Body, kinds: VariableKinds) {
        self.kinds = kinds
        formTable.setKinds(kinds)
        partsTable.setKinds(kinds)
        typeButton.attributedTitle = popTitle(Self.title(body.type))
        typeButton.setAccessibilityValue(Self.title(body.type))
        noneNote.isHidden = body != .none
        kindButton.isHidden = true
        formatButton.isHidden = true
        textBox.isHidden = true
        formTable.isHidden = true
        partsTable.isHidden = true
        switch body {
        case .none:
            coloredKind = nil
        case .multipart(let parts):
            coloredKind = nil
            partsTable.isHidden = false
            partsTable.setParts(parts)
            partsTable.missingFile = model.missingFile
        case .raw(let kind, let text):
            kindButton.isHidden = false
            kindButton.attributedTitle = popTitle(Self.title(kind))
            formatButton.isHidden = kind == .text
            formatButton.toolTip = "Format \(Self.title(kind)) (⇧⌥F)"
            textBox.isHidden = false
            show(text, kind: kind)
        case .formURLEncoded(let rows):
            coloredKind = nil
            formTable.isHidden = false
            formTable.setRows(rows)
        }
    }

    /// Text from outside (a Tab, an undo, a Curl Import) gets a new storage: replacing a large
    /// coloured storage's characters in place ran past ten minutes at 1 MB (environment-facts.md).
    /// The user's own typing is already in the storage and is only recolored.
    private func show(_ text: String, kind: RawKind) {
        if textView.string != text {
            // Typing undo is registered on the storage; its ranges mean nothing in new text.
            undoManager?.removeAllActions(withTarget: storage)
            storage = NSTextStorage(string: text)
            color(storage, kind: kind)
            layoutManager.replaceTextStorage(storage)
            textView.scrollToBeginningOfDocument(nil)
            gutter.lines = LineIndex(text)
        } else if coloredKind != kind || coloredKinds != kinds {
            color(storage, kind: kind)
        }
        coloredKind = kind
    }

    // ponytail: recolors the whole body per keystroke; move it off the main actor if typing in
    // multi-MB bodies lags.
    private func color(_ storage: NSTextStorage, kind: RawKind) {
        let all = NSRange(location: 0, length: storage.length)
        storage.beginEditing()
        storage.setAttributes([.font: font, .foregroundColor: theme.color(.text)], range: all)
        for range in Highlighter.ranges(storage.string, kind: kind) where NSMaxRange(range.range) <= storage.length {
            storage.addAttribute(.foregroundColor, value: theme.color(range.token), range: range.range)
        }
        // On top of the syntax colours, as the Highlighter leaves `{{name}}` alone.
        VariableStyle.apply(kinds, to: storage, disabled: false, theme: theme)
        storage.endEditing()
        coloredKinds = kinds
    }

    func textDidChange(_ notification: Notification) {
        guard case .raw(let kind, _) = model.tab.definition.body else { return }
        color(storage, kind: kind)
        showFormatError(nil)
        model.tab.definition.body = .raw(kind, textView.string)
        // ponytail: every line start again per keystroke, O(n); fine for bodies people type.
        gutter.lines = LineIndex(textView.string)
    }
}

/// The raw body editor, which shows the Variable popover over a `{{name}}`.
final class HoverTextView: VariableTextView {
    var variableHover: VariableHover?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect], owner: self))
    }

    override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        variableHover?.pointerMoved(to: event.locationInWindow)
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        variableHover?.exited()
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        super.viewWillMove(toWindow: newWindow)
        variableHover?.exited()
    }
}

/// A pop-up drawn as a bordered button: 10 pt either side of its title.
final class PopButton: NSButton {
    override var intrinsicContentSize: NSSize {
        NSSize(width: attributedTitle.size().width.rounded(.up) + 20, height: 24)
    }
}

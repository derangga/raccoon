import AppKit
import RaccoonDomain

/// What colours a body editor's text: the raw body's kind, or a GraphQL query.
enum BodySyntax: Equatable {
    case raw(RawKind)
    case graphql

    func ranges(_ text: String) -> [HighlightRange] {
        switch self {
        case .raw(let kind): Highlighter.ranges(text, kind: kind)
        case .graphql: Highlighter.graphql(text)
        }
    }
}

/// One body editor: SF Mono 12 with line numbers, syntax colours and `{{name}}` highlighting inside a
/// `background` box with a 1 pt `border` and a 6 pt radius (design-system.md §6 Body editor). The raw
/// body, the GraphQL Query and the GraphQL Variables each have one.
final class BodyTextEditor: NSView, NSTextViewDelegate {
    private let theme: ThemeEnvironment
    let textView: HoverTextView
    private let scroll = NSScrollView()
    private lazy var gutter: Gutter = {
        let gutter = Gutter(textView: textView, theme: theme)
        gutter.lines = LineIndex("")
        return gutter
    }()
    private let layoutManager = WavyLayoutManager()
    /// The layout manager does not retain its storage, so the view must.
    private var storage = NSTextStorage()
    private var font: NSFont { .monospacedSystemFont(ofSize: 12, weight: .regular) }
    /// What the storage is coloured for, so a change recolors without new text. nil: not shown.
    var syntax: BodySyntax?
    /// The Variables the storage is coloured by; a new Active Environment recolours it.
    private var kinds = VariableKinds(active: nil, globals: Globals(entries: []))
    private var coloredKinds: VariableKinds?
    /// The user typed: the text now in the editor.
    var onChange: (String) -> Void = { _ in }

    /// Drawn in `textTertiary` while the editor is empty; never part of the text.
    var placeholder: String {
        get { textView.placeholder }
        set {
            textView.placeholder = newValue
            textView.setAccessibilityPlaceholderValue(newValue)
        }
    }

    init(theme: ThemeEnvironment) {
        self.theme = theme
        // TextKit 1 with non-contiguous layout, as the Response body (environment-facts.md).
        let container = NSTextContainer(size: NSSize(width: CGFloat.greatestFiniteMagnitude, height: .greatestFiniteMagnitude))
        container.widthTracksTextView = false
        layoutManager.allowsNonContiguousLayout = true
        layoutManager.addTextContainer(container)
        storage.addLayoutManager(layoutManager)
        textView = HoverTextView(frame: .zero, textContainer: container)
        super.init(frame: .zero)
        textView.variableHover = VariableHover(
            layout: { [weak self] in self.map { TextLayout(storage: $0.storage, manager: $0.layoutManager, origin: $0.textView.textContainerOrigin, space: $0.textView) } },
            kinds: { [weak self] in self?.kinds }, theme: { [weak self] in self?.theme }
        )
        textView.suggestions = VariableSuggestions(kinds: { [weak self] in self?.kinds }, theme: { [weak self] in self?.theme })
        build()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    private func build() {
        textView.delegate = self
        textView.isRichText = false
        textView.allowsUndo = true
        textView.drawsBackground = false
        textView.font = font
        wantsLayer = true
        layer?.cornerRadius = 6
        layer?.borderWidth = 1
        layer?.masksToBounds = true
        // The storage keeps the colours of the last pass, so a new Flavor recolours it.
        theme.paint(self) { editor, theme in
            editor.layer?.borderColor = theme.color(.border).cgColor
            editor.layer?.backgroundColor = theme.color(.background).cgColor
            editor.textView.textColor = theme.color(.text)
            editor.textView.insertionPointColor = theme.color(.text)
            editor.textView.placeholderColor = theme.color(.textTertiary)
            editor.textView.typingAttributes = [.font: editor.font, .foregroundColor: theme.color(.text)]
            if let syntax = editor.syntax { editor.color(editor.storage, syntax: syntax) }
        }
        for substitution in [\NSTextView.isAutomaticQuoteSubstitutionEnabled, \.isAutomaticDashSubstitutionEnabled,
                             \.isAutomaticTextReplacementEnabled, \.isAutomaticSpellingCorrectionEnabled] {
            textView[keyPath: substitution] = false
        }
        textView.textContainerInset = NSSize(width: 4, height: 8)
        textView.usesFindBar = true
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

        scroll.translatesAutoresizingMaskIntoConstraints = false
        addSubview(scroll)
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: topAnchor, constant: 1),
            scroll.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 1),
            scroll.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -1),
            scroll.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -1),
        ])
    }

    /// Text from outside (a Tab, an undo, a Curl Import) gets a new storage: replacing a large
    /// coloured storage's characters in place ran past ten minutes at 1 MB (environment-facts.md).
    /// The user's own typing is already in the storage and is only recolored.
    func show(_ text: String, syntax: BodySyntax, kinds: VariableKinds) {
        self.kinds = kinds
        if textView.string != text {
            // Typing undo is registered on the storage; its ranges mean nothing in new text.
            undoManager?.removeAllActions(withTarget: storage)
            storage = NSTextStorage(string: text)
            color(storage, syntax: syntax)
            layoutManager.replaceTextStorage(storage)
            textView.scrollToBeginningOfDocument(nil)
            gutter.lines = LineIndex(text)
            textView.needsDisplay = true
        } else if self.syntax != syntax || coloredKinds != kinds {
            color(storage, syntax: syntax)
        }
        self.syntax = syntax
    }

    // ponytail: recolors the whole body per keystroke; move it off the main actor if typing in
    // multi-MB bodies lags.
    private func color(_ storage: NSTextStorage, syntax: BodySyntax) {
        let all = NSRange(location: 0, length: storage.length)
        storage.beginEditing()
        storage.setAttributes([.font: font, .foregroundColor: theme.color(.text)], range: all)
        for range in syntax.ranges(storage.string) where NSMaxRange(range.range) <= storage.length {
            storage.addAttribute(.foregroundColor, value: theme.color(range.token), range: range.range)
        }
        // On top of the syntax colours, as the Highlighter leaves `{{name}}` alone.
        VariableStyle.apply(kinds, to: storage, disabled: false, theme: theme)
        storage.endEditing()
        coloredKinds = kinds
    }

    func textDidChange(_ notification: Notification) {
        guard let syntax else { return }
        color(storage, syntax: syntax)
        onChange(textView.string)
        // ponytail: every line start again per keystroke, O(n); fine for bodies people type.
        gutter.lines = LineIndex(textView.string)
    }
}

/// The body editors' text view, which shows the Variable popover over a `{{name}}` and draws the
/// placeholder while it is empty.
final class HoverTextView: VariableTextView {
    var variableHover: VariableHover?
    var placeholder = ""
    var placeholderColor = NSColor.placeholderTextColor {
        didSet { needsDisplay = true }
    }

    /// Typing may not dirty the whole placeholder, so the view is redrawn once the text changes.
    override func didChangeText() {
        super.didChangeText()
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard string.isEmpty, !placeholder.isEmpty, let font else { return }
        let origin = NSPoint(x: textContainerOrigin.x + (textContainer?.lineFragmentPadding ?? 0), y: textContainerOrigin.y)
        NSAttributedString(string: placeholder, attributes: [.font: font, .foregroundColor: placeholderColor]).draw(at: origin)
    }

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

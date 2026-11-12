import AppKit
import RaccoonDomain

/// The Docs section: one editor filling the pane, the Request's Docs styled as they are typed
/// (design-system.md §6 Docs pane). The marks stay in the text; only attributes change.
final class DocsPane: NSView, NSTextViewDelegate {
    /// The text after each edit the user makes.
    var onChange: ((String) -> Void)?

    static let placeholder = "Notes for this Request, in markdown."

    private let theme: ThemeEnvironment
    let textView: DocsTextView
    private let scroll = NSScrollView()

    init(theme: ThemeEnvironment) {
        self.theme = theme
        // TextKit 1, as the other editors: the styling is attributes on the one storage.
        textView = DocsTextView(usingTextLayoutManager: false)
        super.init(frame: .zero)
        textView.delegate = self
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.drawsBackground = false
        textView.usesFindBar = true
        textView.isIncrementalSearchingEnabled = true
        textView.isContinuousSpellCheckingEnabled = true
        // Typed text is saved as typed: a smart quote or dash would rewrite it.
        for substitution in [\NSTextView.isAutomaticQuoteSubstitutionEnabled, \.isAutomaticDashSubstitutionEnabled,
                             \.isAutomaticTextReplacementEnabled, \.isAutomaticSpellingCorrectionEnabled] {
            textView[keyPath: substitution] = false
        }
        // With the 5 pt line padding: 16 pt in from the pane's sides and from its top.
        textView.textContainerInset = NSSize(width: 11, height: 16)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: .greatestFiniteMagnitude)
        textView.setAccessibilityLabel("Docs")
        scroll.documentView = textView
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false
        scroll.translatesAutoresizingMaskIntoConstraints = false
        addSubview(scroll)
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: topAnchor),
            scroll.leadingAnchor.constraint(equalTo: leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        theme.paint(self) { pane, theme in
            pane.textView.insertionPointColor = theme.color(.text)
            pane.textView.linkTextAttributes = [.foregroundColor: theme.color(.accent)]
            pane.textView.placeholderColor = theme.color(.textDisabled)
            pane.style()
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// Text from outside (a Tab, an undo, a reload): the user's own typing is already in the
    /// editor and is left alone, caret and all.
    func setDocs(_ text: String) {
        guard textView.string != text else { return }
        // Typing undo is registered against the old text; its ranges mean nothing in the new.
        undoManager?.removeAllActions(withTarget: textView)
        if let storage = textView.textStorage { undoManager?.removeAllActions(withTarget: storage) }
        textView.string = text
        style()
        textView.scrollToBeginningOfDocument(nil)
    }

    func textDidChange(_ notification: Notification) {
        // Styling during composition would strip the marked-text attributes; the commit restyles.
        if !textView.hasMarkedText() { style() }
        onChange?(textView.string)
    }

    private static let body = NSFont.systemFont(ofSize: 13)
    private static let mono = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)

    // shortcut: restyles all of the Docs per keystroke, O(n); upgrade if Docs grow past a few pages.
    private func style() {
        guard let storage = textView.textStorage else { return }
        let all = NSRange(location: 0, length: storage.length)
        storage.beginEditing()
        storage.setAttributes([.font: Self.body, .foregroundColor: theme.color(.text)], range: all)
        for styled in DocsStyle.ranges(storage.string) where NSMaxRange(styled.range) <= storage.length {
            storage.addAttributes(attributes(for: styled.style), range: styled.range)
        }
        storage.endEditing()
        textView.typingAttributes = [.font: Self.body, .foregroundColor: theme.color(.text)]
    }

    private func attributes(for style: DocsStyle.Style) -> [NSAttributedString.Key: Any] {
        switch style {
        case .mark: [.foregroundColor: theme.color(.textTertiary)]
        case .heading(let level): [.font: NSFont.systemFont(ofSize: [20, 17, 15][min(level, 3) - 1], weight: .semibold)]
        case .bold: [.font: NSFont.systemFont(ofSize: 13, weight: .semibold)]
        case .italic: [.font: NSFontManager.shared.convert(Self.body, toHaveTrait: .italicFontMask)]
        case .code, .codeBlock: [.font: Self.mono, .backgroundColor: theme.color(.backgroundRecessed)]
        case .listMarker, .quoteMark, .quote: [.foregroundColor: theme.color(.textSecondary)]
        case .link(let url):
            [.foregroundColor: theme.color(.accent)].merging(url.flatMap(URL.init(string:)).map { [.link: $0] } ?? [:]) { $1 }
        }
    }
}

/// The Docs editor: the placeholder while empty, and ⌘-click opens a link.
final class DocsTextView: NSTextView {
    var placeholderColor = NSColor.placeholderTextColor {
        didSet { needsDisplay = true }
    }

    override func didChangeText() {
        super.didChangeText()
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard string.isEmpty else { return }
        let origin = NSPoint(x: textContainerInset.width + (textContainer?.lineFragmentPadding ?? 0), y: textContainerInset.height)
        NSAttributedString(string: DocsPane.placeholder, attributes: [.font: NSFont.systemFont(ofSize: 13), .foregroundColor: placeholderColor])
            .draw(at: origin)
    }

    override func mouseDown(with event: NSEvent) {
        guard event.modifierFlags.contains(.command), let layout = layoutManager, let container = textContainer, let storage = textStorage else {
            return super.mouseDown(with: event)
        }
        let point = convert(event.locationInWindow, from: nil)
        let inContainer = NSPoint(x: point.x - textContainerOrigin.x, y: point.y - textContainerOrigin.y)
        let index = layout.characterIndex(for: inContainer, in: container, fractionOfDistanceBetweenInsertionPoints: nil)
        guard index < storage.length, let url = storage.attribute(.link, at: index, effectiveRange: nil) as? URL else {
            return super.mouseDown(with: event)
        }
        NSWorkspace.shared.open(url)
    }
}

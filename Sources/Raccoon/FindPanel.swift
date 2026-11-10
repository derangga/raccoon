import AppKit
import RaccoonDomain

/// The Find panel (design-system.md): floats over a Response body's top-right corner. It draws
/// and reports; the viewer searches. It appears and goes with no animation: ⌘F is used many
/// times a day.
final class FindPanel: NSView, NSTextFieldDelegate {
    let field = NSTextField()
    let countLabel = NSTextField(labelWithString: "")
    let previousButton: IconButton
    let nextButton: IconButton
    let closeButton: IconButton
    private let theme: ThemeEnvironment
    private var editing = false

    /// The query as typed, every keystroke.
    var onQuery: (String) -> Void = { _ in }
    var onStep: (_ forward: Bool) -> Void = { _ in }
    var onClose: () -> Void = {}

    init(theme: ThemeEnvironment) {
        self.theme = theme
        previousButton = IconButton(symbol: "chevron.up", label: "Previous (⇧⌘G)", side: 20, theme: theme)
        nextButton = IconButton(symbol: "chevron.down", label: "Next (⌘G)", side: 20, theme: theme)
        closeButton = IconButton(symbol: "xmark", label: "Close (Esc)", side: 20, theme: theme)
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 8
        layer?.masksToBounds = false
        // The Dropdown list's shadow, drawn on the panel, not the system's window shadow.
        layer?.shadowOpacity = 0.12
        layer?.shadowRadius = 6
        layer?.shadowOffset = CGSize(width: 0, height: -4)
        layer?.shadowColor = NSColor.black.cgColor
        setAccessibilityRole(.group)
        setAccessibilityLabel("Find")

        let glyph = NSImageView(image: NSImage(systemSymbolName: "magnifyingglass", accessibilityDescription: nil) ?? NSImage())
        glyph.symbolConfiguration = .init(pointSize: 13, weight: .regular)
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        field.cell?.isScrollable = true
        field.cell?.wraps = false
        field.delegate = self
        field.setAccessibilityLabel("Find in the Response body")
        field.setContentHuggingPriority(.init(1), for: .horizontal)
        field.setContentCompressionResistancePriority(.init(1), for: .horizontal)
        countLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        countLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        for (button, action) in [(previousButton, #selector(previous)), (nextButton, #selector(next)), (closeButton, #selector(close))] {
            button.target = self
            button.action = action
        }
        theme.paint(self) { panel, theme in
            panel.layer?.backgroundColor = theme.color(.backgroundElevated).cgColor
            panel.drawBorder()
            glyph.contentTintColor = theme.color(.textTertiary)
            panel.field.textColor = theme.color(.text)
            panel.field.placeholderAttributedString = NSAttributedString(string: "Find", attributes: [
                .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular), .foregroundColor: theme.color(.textTertiary),
            ])
            panel.countLabel.textColor = theme.color(.textTertiary)
        }

        let row = NSStackView(views: [glyph, field, countLabel, previousButton, nextButton, closeButton])
        row.spacing = 6
        row.setCustomSpacing(2, after: previousButton)
        row.setCustomSpacing(2, after: nextButton)
        row.edgeInsets = NSEdgeInsets(top: 0, left: 8, bottom: 0, right: 6)
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)
        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 320),
            heightAnchor.constraint(equalToConstant: 32),
            row.topAnchor.constraint(equalTo: topAnchor),
            row.bottomAnchor.constraint(equalTo: bottomAnchor),
            row.leadingAnchor.constraint(equalTo: leadingAnchor),
            row.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// Shows the panel and puts the caret in its field with the last query selected.
    func open() {
        isHidden = false
        window?.makeFirstResponder(field)
        field.currentEditor()?.selectAll(nil)
    }

    /// "2 of 7"; the chevrons are off while there is nothing to step through.
    func show(count: String, canStep: Bool) {
        countLabel.stringValue = count
        previousButton.isEnabled = canStep
        nextButton.isEnabled = canStep
    }

    @objc private func previous() { onStep(false) }
    @objc private func next() { onStep(true) }
    @objc private func close() { onClose() }

    /// 1 pt `border` at 50 %, or the 2 pt focus ring while the field is being typed in.
    private func drawBorder() {
        layer?.borderWidth = editing ? 2 : 1
        layer?.borderColor = (editing ? theme.color(.focusRing) : theme.color(.border).withAlphaComponent(0.5)).cgColor
    }

    // MARK: NSTextFieldDelegate

    func controlTextDidBeginEditing(_ notification: Notification) {
        editing = true
        drawBorder()
    }

    func controlTextDidEndEditing(_ notification: Notification) {
        editing = false
        drawBorder()
    }

    func controlTextDidChange(_ notification: Notification) {
        onQuery(field.stringValue)
    }

    /// Return steps forward, ⇧Return back, Esc closes.
    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        switch selector {
        case #selector(NSResponder.insertNewline(_:)):
            onStep(!(NSApp.currentEvent?.modifierFlags.contains(.shift) ?? false))
        case #selector(NSResponder.cancelOperation(_:)):
            onClose()
        default:
            return false
        }
        return true
    }

    /// ⌘G and ⇧⌘G step, and ⌘F selects the query, while the field has focus: the field editor
    /// would otherwise take them before the menu reaches the viewer.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard !isHidden, editing, event.modifierFlags.intersection(.deviceIndependentFlagsMask).subtracting(.shift) == .command else {
            return super.performKeyEquivalent(with: event)
        }
        switch event.charactersIgnoringModifiers?.lowercased() {
        case "g": onStep(!event.modifierFlags.contains(.shift))
        case "f": field.currentEditor()?.selectAll(nil)
        default: return super.performKeyEquivalent(with: event)
        }
        return true
    }
}

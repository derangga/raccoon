import AppKit
import RaccoonDomain

/// A borderless symbol button in the Theme (design-system.md, Icon button): `rowHover` under the
/// pointer, `selection` while pressed, from mouse-down, and the symbol in `textDisabled` when off.
final class IconButton: NSButton {
    private let theme: ThemeEnvironment
    private let glyph = NSImageView()
    private var symbol: String
    private var hovered = false
    private var pressed = false
    private var flashing: Task<Void, Never>?

    init(symbol: String, label: String, side: CGFloat = 24, theme: ThemeEnvironment) {
        self.theme = theme
        self.symbol = symbol
        super.init(frame: .zero)
        title = ""
        isBordered = false
        wantsLayer = true
        layer?.cornerRadius = 6
        toolTip = label
        setAccessibilityLabel(label)
        glyph.symbolConfiguration = .init(pointSize: 13, weight: .regular)
        glyph.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        glyph.translatesAutoresizingMaskIntoConstraints = false
        addSubview(glyph)
        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: side),
            heightAnchor.constraint(equalToConstant: side),
            glyph.centerXAnchor.constraint(equalTo: centerXAnchor),
            glyph.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        theme.paint(self) { button, _ in button.redraw() }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var isEnabled: Bool {
        didSet {
            if !isEnabled { hovered = false }
            redraw()
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self))
    }

    override func mouseEntered(with event: NSEvent) {
        hovered = isEnabled
        redraw()
    }

    override func mouseExited(with event: NSEvent) {
        hovered = false
        redraw()
    }

    /// Pressed from mouse-down: NSButton tracks the click inside `super` and returns on mouse-up.
    override func mouseDown(with event: NSEvent) {
        guard isEnabled else { return super.mouseDown(with: event) }
        pressed = true
        redraw()
        displayIfNeeded()
        super.mouseDown(with: event)
        pressed = false
        redraw()
    }

    /// Shows `symbol` for `seconds`, then the button's own again: Copy's "Copied".
    func flash(_ symbol: String, tooltip: String, for seconds: Double) {
        let own = (self.symbol, toolTip)
        swap(to: symbol)
        toolTip = tooltip
        flashing?.cancel()
        flashing = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard let self, !Task.isCancelled else { return }
            swap(to: own.0)
            toolTip = own.1
        }
    }

    /// The system's symbol replace, which already honours Reduce Motion.
    private func swap(to symbol: String) {
        guard let image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil) else { return }
        glyph.setSymbolImage(image, contentTransition: .replace)
    }

    private func redraw() {
        let fill: ColorToken? = pressed && isEnabled ? .selection : hovered ? .rowHover : nil
        layer?.backgroundColor = fill.map { theme.color($0).cgColor } ?? NSColor.clear.cgColor
        glyph.contentTintColor = theme.color(!isEnabled ? .textDisabled : hovered || pressed ? .text : .textSecondary)
    }
}

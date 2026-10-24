import AppKit
import RaccoonDomain

extension NSAttributedString.Key {
    /// An Undefined Variable's 1 pt wavy underline, in this colour. AppKit has no wavy underline
    /// style, so WavyLayoutManager and VariableFieldCell draw it.
    nonisolated static let wavyUnderline = NSAttributedString.Key("RaccoonWavyUnderline")
}

/// `{{name}}` highlighting (design-system §6 URL bar): defined in `variableDefined`, secret in
/// `variableSecret` with a dotted underline, undefined in `variableUndefined` with a wavy one, so
/// undefined is never shown by colour alone. In a Disabled Row all three are `textDisabled`.
enum VariableStyle {
    static func apply(_ kinds: VariableKinds, to text: NSMutableAttributedString, disabled: Bool, theme: ThemeEnvironment) {
        let all = NSRange(location: 0, length: text.length)
        for key in [NSAttributedString.Key.underlineStyle, .underlineColor, .wavyUnderline] { text.removeAttribute(key, range: all) }
        for range in kinds.ranges(in: text.string) where NSMaxRange(range.range) <= text.length {
            let color = theme.color(disabled ? .textDisabled : range.token)
            text.addAttribute(.foregroundColor, value: color, range: range.range)
            switch range.token {
            case .variableSecret:
                text.addAttributes([.underlineStyle: NSUnderlineStyle([.single, .patternDot]).rawValue, .underlineColor: color], range: range.range)
            case .variableUndefined:
                text.addAttribute(.wavyUnderline, value: color, range: range.range)
            default:
                break
            }
        }
    }

    /// Waves under every `.wavyUnderline` run in `glyphs`, one per line fragment, with the text
    /// container's origin at `origin`.
    nonisolated static func drawWaves(_ manager: NSLayoutManager, glyphs: NSRange, at origin: NSPoint) {
        guard let storage = manager.textStorage else { return }
        let characters = manager.characterRange(forGlyphRange: glyphs, actualGlyphRange: nil)
        storage.enumerateAttribute(.wavyUnderline, in: characters) { value, range, _ in
            guard let color = value as? NSColor else { return }
            let run = manager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            manager.enumerateLineFragments(forGlyphRange: run) { _, _, container, line, _ in
                let rect = manager.boundingRect(forGlyphRange: NSIntersectionRange(run, line), in: container)
                wave(from: origin.x + rect.minX, to: origin.x + rect.maxX, y: origin.y + rect.maxY - 1.5, color: color)
            }
        }
    }

    /// 1 pt, 4 pt per period, 1.5 pt either side of `y`. Flipped views only, as text views are.
    nonisolated private static func wave(from start: CGFloat, to end: CGFloat, y: CGFloat, color: NSColor) {
        guard end > start else { return }
        let path = NSBezierPath()
        path.lineWidth = 1
        path.move(to: NSPoint(x: start, y: y))
        var x = start
        while x < end {
            let next = min(x + 4, end)
            let step = next - x
            path.curve(to: NSPoint(x: next, y: y), controlPoint1: NSPoint(x: x + step / 4, y: y - 3), controlPoint2: NSPoint(x: x + step * 3 / 4, y: y + 3))
            x = next
        }
        color.setStroke()
        path.stroke()
    }

    /// A TextKit 1 field editor whose layout manager draws the waves while a field is edited.
    static func fieldEditor<Editor: NSTextView>(_ type: Editor.Type) -> Editor {
        let editor = Editor(usingTextLayoutManager: false)
        editor.isFieldEditor = true
        editor.textContainer?.replaceLayoutManager(WavyLayoutManager())
        return editor
    }
}

/// TextKit 1 layout that draws `.wavyUnderline` after the glyphs: the raw body editor and every
/// field editor of a VariableField.
nonisolated final class WavyLayoutManager: NSLayoutManager {
    override func drawGlyphs(forGlyphRange glyphsToShow: NSRange, at origin: NSPoint) {
        super.drawGlyphs(forGlyphRange: glyphsToShow, at: origin)
        VariableStyle.drawWaves(self, glyphs: glyphsToShow, at: origin)
    }
}

/// A text field that takes Variables: its `{{name}}`s are coloured at rest, on every keystroke
/// while edited, and again whenever `kinds` changes. Without `kinds` it is a plain field.
class VariableField: NSTextField {
    var theme: ThemeEnvironment?
    var kinds: VariableKinds? {
        didSet { if kinds != oldValue { highlight() } }
    }
    /// The row is not sent, so its Variables are not resolved: `textDisabled`.
    var isDisabledRow = false
    /// Made on first edit only: a table makes a field per cell on every reload.
    private(set) lazy var editor: VariableTextView = {
        let editor = VariableStyle.fieldEditor(VariableTextView.self)
        editor.suggestions = suggestions
        return editor
    }()

    /// Typing `{{` in the field offers the names in `kinds`.
    private(set) lazy var suggestions = VariableSuggestions(kinds: { [weak self] in self?.kinds }, theme: { [weak self] in self?.theme })

    override class var cellClass: AnyClass? {
        get { VariableFieldCell.self }
        set {}
    }

    /// Recolours the text the field shows, or its editor's while it is edited.
    func highlight() {
        guard let kinds, let theme else { return }
        if let editor = currentEditor() as? NSTextView, let storage = editor.textStorage {
            let base = textColor ?? theme.color(.text)
            storage.beginEditing()
            storage.addAttribute(.foregroundColor, value: base, range: NSRange(location: 0, length: storage.length))
            VariableStyle.apply(kinds, to: storage, disabled: isDisabledRow, theme: theme)
            storage.endEditing()
            // Typing after a token must not continue its colour.
            editor.typingAttributes[.foregroundColor] = base
            for key in [NSAttributedString.Key.underlineStyle, .underlineColor, .wavyUnderline] { editor.typingAttributes[key] = nil }
            // The editor draws its own waves.
            waves?.isHidden = true
        } else {
            let text = NSMutableAttributedString(attributedString: attributedStringValue)
            VariableStyle.apply(kinds, to: text, disabled: isDisabledRow, theme: theme)
            attributedStringValue = text
            showWaves(text)
        }
    }

    /// At rest, a click-through subview draws the waves: overriding the cell's drawing would
    /// change how AppKit draws every field's text, waves or not.
    private var waves: WaveOverlay?

    private func showWaves(_ text: NSAttributedString) {
        var hasWave = false
        text.enumerateAttribute(.wavyUnderline, in: NSRange(location: 0, length: text.length)) { value, _, stop in
            if value != nil { hasWave = true; stop.pointee = true }
        }
        guard hasWave else { waves?.isHidden = true; return }
        let overlay = overlay()
        overlay.isHidden = false
        overlay.needsDisplay = true
    }

    private func overlay() -> WaveOverlay {
        if let waves { return waves }
        let overlay = WaveOverlay(frame: bounds)
        overlay.autoresizingMask = [.width, .height]
        addSubview(overlay)
        waves = overlay
        return overlay
    }

    // MARK: Hover

    /// The text where the pointer is over it: the field editor's while edited, else the field's
    /// string laid out where its cell draws it.
    private func hoverLayout() -> TextLayout? {
        if let editor = currentEditor() as? NSTextView, let manager = editor.layoutManager, let storage = editor.textStorage {
            return TextLayout(storage: storage, manager: manager, origin: editor.textContainerOrigin, space: editor)
        }
        return TextLayout.atRest(self, space: overlay())
    }

    private lazy var hover = VariableHover(
        layout: { [weak self] in self?.hoverLayout() }, kinds: { [weak self] in self?.kinds }, theme: { [weak self] in self?.theme }
    )

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect], owner: self))
    }

    override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        hover.pointerMoved(to: event.locationInWindow)
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        hover.exited()
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        super.viewWillMove(toWindow: newWindow)
        hover.exited()
    }

    override func becomeFirstResponder() -> Bool {
        let became = super.becomeFirstResponder()
        if became { highlight() }
        return became
    }

    override func textDidChange(_ notification: Notification) {
        super.textDidChange(notification)
        highlight()
    }

    override func textDidEndEditing(_ notification: Notification) {
        super.textDidEndEditing(notification)
        highlight()
    }
}

/// Hands its field its own wave-drawing editor.
class VariableFieldCell: NSTextFieldCell {
    override func fieldEditor(for controlView: NSView) -> NSTextView? {
        (controlView as? VariableField)?.editor ?? super.fieldEditor(for: controlView)
    }
}

/// The waves of a field or label at rest, from a TextKit 1 layout of its string laid where its
/// cell draws it.
final class WaveOverlay: NSView {
    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        guard let field = superview as? NSTextField, let cell = field.cell else { return }
        let layout = TextLayout.atRest(field, space: self)
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(rect: cell.drawingRect(forBounds: field.bounds)).addClip()
        VariableStyle.drawWaves(layout.manager, glyphs: layout.manager.glyphRange(for: layout.manager.textContainers[0]), at: layout.origin)
        NSGraphicsContext.restoreGraphicsState()
    }
}

extension TextLayout {
    /// `field`'s string laid out where its cell draws it, in `space` (flipped, the field's bounds).
    static func atRest(_ field: NSTextField, space: NSView) -> TextLayout {
        let storage = NSTextStorage(attributedString: field.attributedStringValue)
        let manager = NSLayoutManager()
        let container = NSTextContainer(size: NSSize(width: CGFloat.greatestFiniteMagnitude, height: .greatestFiniteMagnitude))
        // What a text field cell lays its text out with.
        container.lineFragmentPadding = 2
        manager.addTextContainer(container)
        storage.addLayoutManager(manager)
        return TextLayout(storage: storage, manager: manager, origin: field.cell?.drawingRect(forBounds: field.bounds).origin ?? .zero, space: space)
    }
}

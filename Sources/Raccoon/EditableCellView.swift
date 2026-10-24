import AppKit

/// A table cell whose field is the whole cell, as in Postman: while the field is focused, the
/// cell's own bounds carry a square 2 pt outline on `fill`, and the text stays where it was at rest.
/// A click anywhere in the cell goes to the field.
final class EditableCellView: NSTableCellView {
    var ring: NSColor { didSet { applyColors() } }
    var fill: NSColor { didSet { applyColors() } }
    fileprivate(set) var isEditing = false {
        didSet { if isEditing != oldValue { applyColors() } }
    }

    /// `field` sits `inset` in from each side. A field whose cell centres its own text (KeyFieldCell)
    /// is as tall as the row; any other is one line tall in the middle of it.
    init(field: NSTextField, inset: CGFloat, centersOwnText: Bool = false, ring: NSColor, fill: NSColor) {
        self.ring = ring
        self.fill = fill
        super.init(frame: .zero)
        CellFocus.shared.start()
        wantsLayer = true
        textField = field
        field.focusRingType = .none
        field.translatesAutoresizingMaskIntoConstraints = false
        addSubview(field)
        NSLayoutConstraint.activate([
            field.leadingAnchor.constraint(equalTo: leadingAnchor, constant: inset),
            field.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -inset),
        ] + (centersOwnText
            ? [field.topAnchor.constraint(equalTo: topAnchor), field.bottomAnchor.constraint(equalTo: bottomAnchor)]
            : [field.centerYAnchor.constraint(equalTo: centerYAnchor)]))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil { isEditing = false }
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let hit = super.hitTest(point)
        guard hit === self, let field = textField, field.isEditable else { return hit }
        return field
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyColors()
    }

    private func applyColors() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.borderWidth = isEditing ? 2 : 0
            layer?.cornerRadius = 0
            layer?.borderColor = ring.cgColor
            layer?.backgroundColor = isEditing ? fill.cgColor : nil
        }
    }
}

/// Which cell is being edited, from focus rather than the first keystroke: AppKit says editing
/// began only once the text changes. The field editor sets its selection when a field takes
/// focus, and the field says when editing ends, typed or not. One observer for every cell.
private final class CellFocus: NSObject {
    static let shared = CellFocus()
    private var started = false

    func start() {
        guard !started else { return }
        started = true
        NotificationCenter.default.addObserver(self, selector: #selector(selectionChanged), name: NSTextView.didChangeSelectionNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(editingEnded), name: NSControl.textDidEndEditingNotification, object: nil)
    }

    @objc private func selectionChanged(_ note: Notification) {
        guard let editor = note.object as? NSTextView, editor.isFieldEditor,
              let cell = (editor.delegate as? NSView)?.superview as? EditableCellView else { return }
        cell.isEditing = true
    }

    @objc private func editingEnded(_ note: Notification) {
        ((note.object as? NSView)?.superview as? EditableCellView)?.isEditing = false
    }
}

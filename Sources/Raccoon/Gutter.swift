import AppKit
import RaccoonDomain

/// Line numbers left of a body, then a fold column with a chevron beside every line that opens
/// a Fold Region in a Pretty Response (design-system.md §6 Response viewer). Numbers come from
/// a precomputed LineIndex, so a draw reads only the lines on screen.
final class Gutter: NSRulerView {
    private let theme: ThemeEnvironment
    private let font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)

    /// nil draws nothing: the Response's lines arrive with the off-main presentation.
    var lines: LineIndex? {
        didSet {
            let digits = String(lines?.starts.count ?? 1).count
            let width = NSAttributedString(string: "0", attributes: [.font: font]).size().width
            ruleThickness = max(50, (8 + CGFloat(digits) * width + Self.foldColumn).rounded(.up))
            needsDisplay = true
        }
    }

    private(set) var regions: [FoldRegion] = []
    private var opens: [Int: FoldRegion] = [:]
    private(set) var folds = FoldSet()
    private(set) var shown = FoldedText(regions: [], folds: FoldSet())
    /// A click on a line with a chevron.
    var toggle: ((FoldRegion) -> Void)?

    /// Between the numbers and the text.
    private static let foldColumn: CGFloat = 16

    /// Unfolded chevrons show only while the pointer is over the Gutter.
    var isPointerInside = false {
        didSet { needsDisplay = true }
    }

    init(textView: NSTextView, theme: ThemeEnvironment) {
        self.theme = theme
        super.init(scrollView: nil, orientation: .verticalRuler)
        clientView = textView
        ruleThickness = 50
        NotificationCenter.default.addObserver(self, selector: #selector(redraw), name: NSView.boundsDidChangeNotification, object: nil)
    }

    @available(*, unavailable)
    required init(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func show(regions: [FoldRegion], folds: FoldSet, shown: FoldedText) {
        if regions != self.regions {
            self.regions = regions
            opens = Dictionary(regions.map { ($0.openLine, $0) }, uniquingKeysWith: { first, _ in first })
        }
        self.folds = folds
        self.shown = shown
        needsDisplay = true
    }

    @objc private func redraw(_ notification: Notification) {
        if (notification.object as? NSClipView) === scrollView?.contentView { needsDisplay = true }
    }

    /// One drawn line: its 1-based number, where it sits, and its chevron, true when folded.
    struct Row {
        var line: Int
        var top: CGFloat
        var chevron: Bool?
        var number: Int { line + 1 }
    }

    /// The lines on screen, in the client view's coordinates, skipping folded ones.
    func rows() -> [Row] {
        guard let lines, let textView = clientView as? NSTextView, let layout = textView.layoutManager,
              let container = textView.textContainer, let storage = textView.textStorage else { return [] }
        let text = storage.string as NSString
        let inset = textView.textContainerOrigin.y
        guard text.length > 0 else { return [Row(line: 0, top: inset, chevron: nil)] }
        let glyphs = layout.glyphRange(forBoundingRect: textView.visibleRect, in: container)
        let visible = layout.characterRange(forGlyphRange: glyphs, actualGlyphRange: nil)
        let first = text.lineRange(for: NSRange(location: min(visible.location, text.length - 1), length: 0)).location
        var line = lines.line(containing: shown.source(first))
        var rows: [Row] = []
        while line < lines.starts.count {
            let at = shown.display(lines.starts[line])
            guard at <= NSMaxRange(visible) else { break }
            // The empty line after a final line break has no glyph, only the extra fragment.
            let fragment = at == text.length ? layout.extraLineFragmentRect : layout.lineFragmentRect(forGlyphAt: layout.glyphIndexForCharacter(at: at), effectiveRange: nil)
            rows.append(Row(line: line, top: fragment.minY + inset, chevron: opens[line].map(folds.isFolded)))
            line = shown.nextLine(after: line)
        }
        return rows
    }

    func showsChevron(_ row: Row) -> Bool {
        row.chevron == true || (row.chevron == false && isPointerInside)
    }

    /// An indent guide, in the client view's coordinates.
    struct Guide {
        /// Columns before the opening line's text.
        var indent: Int
        var top: CGFloat
        var bottom: CGFloat
    }

    /// One per unfolded Fold Region on screen, from under its opening line to its closing line.
    func guides() -> [Guide] {
        let rows = rows()
        guard let lines, let first = rows.first, let last = rows.last, let textView = clientView as? NSTextView,
              let storage = textView.textStorage else { return [] }
        let tops = Dictionary(rows.map { ($0.line, $0.top) }, uniquingKeysWith: { first, _ in first })
        let text = storage.string as NSString
        var guides: [Guide] = []
        for region in regions {
            guard region.openLine < last.line else { break }
            guard region.closeLine > first.line, !folds.isFolded(region), !shown.isHidden(line: region.openLine) else { continue }
            var indent = 0
            let start = shown.display(lines.starts[region.openLine])
            while start + indent < text.length, text.character(at: start + indent) == 0x20 { indent += 1 }
            let top = tops[region.openLine + 1] ?? textView.visibleRect.minY
            let bottom = tops[region.closeLine] ?? textView.visibleRect.maxY
            guides.append(Guide(indent: indent, top: top, bottom: bottom))
        }
        return guides
    }

    /// No fill and no divider: the Gutter sits on the body's own background.
    override func draw(_ dirtyRect: NSRect) {
        drawHashMarksAndLabels(in: dirtyRect)
    }

    override func drawHashMarksAndLabels(in rect: NSRect) {
        guard let textView = clientView as? NSTextView else { return }
        let color = theme.color(.textTertiary)
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
        let right = ruleThickness - Self.foldColumn
        let symbol = NSImage.SymbolConfiguration(pointSize: 9, weight: .semibold).applying(.init(paletteColors: [color]))
        for row in rows() {
            let y = convert(NSPoint(x: 0, y: row.top), from: textView).y
            let label = NSAttributedString(string: "\(row.number)", attributes: attributes)
            label.draw(at: NSPoint(x: right - label.size().width, y: y))
            guard showsChevron(row), let folded = row.chevron,
                  let image = NSImage(systemSymbolName: folded ? "chevron.right" : "chevron.down", accessibilityDescription: folded ? "Unfold" : "Fold")?
                      .withSymbolConfiguration(symbol) else { continue }
            let height = label.size().height
            image.draw(in: NSRect(x: right + (Self.foldColumn - image.size.width) / 2, y: y + (height - image.size.height) / 2,
                                  width: image.size.width, height: image.size.height))
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self))
    }

    override func mouseEntered(with event: NSEvent) { isPointerInside = true }
    override func mouseExited(with event: NSEvent) { isPointerInside = false }

    override func mouseDown(with event: NSEvent) {
        guard let textView = clientView as? NSTextView else { return }
        let y = textView.convert(event.locationInWindow, from: nil).y
        // The last row starting above the click is the one under it.
        guard let row = rows().last(where: { $0.top <= y }), let region = opens[row.line] else { return }
        toggle?(region)
    }
}

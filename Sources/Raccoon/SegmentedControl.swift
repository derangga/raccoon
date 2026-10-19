import AppKit
import RaccoonDomain

/// The segmented control of design-system.md: a 1 pt `border`, 6 pt radius, `backgroundElevated`
/// box of 22 pt segments split by 1 pt rules. The selected one is `selection` and semibold,
/// a disabled one `textDisabled`. It answers the parts of NSSegmentedControl the panes use.
final class SegmentedControl: NSControl {
    private let theme: ThemeEnvironment
    private var labels: [String]
    private var segmentEnabled: [Bool]
    var selectedSegment = -1 { didSet { needsDisplay = true } }
    var segmentCount: Int { labels.count }

    init(labels: [String], theme: ThemeEnvironment) {
        self.labels = labels
        self.theme = theme
        segmentEnabled = Array(repeating: true, count: labels.count)
        super.init(frame: .zero)
        setAccessibilityRole(.radioGroup)
        theme.paint(self) { control, _ in control.needsDisplay = true }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func label(forSegment index: Int) -> String? { labels.indices.contains(index) ? labels[index] : nil }

    func setLabel(_ label: String, forSegment index: Int) {
        guard labels.indices.contains(index) else { return }
        labels[index] = label
        invalidateIntrinsicContentSize()
        needsDisplay = true
    }

    func isEnabled(forSegment index: Int) -> Bool { segmentEnabled.indices.contains(index) && segmentEnabled[index] }

    func setEnabled(_ isEnabled: Bool, forSegment index: Int) {
        guard segmentEnabled.indices.contains(index) else { return }
        segmentEnabled[index] = isEnabled
        needsDisplay = true
    }

    override var isFlipped: Bool { true }

    private func font(selected: Bool) -> NSFont { .systemFont(ofSize: 12, weight: selected ? .semibold : .regular) }

    /// Sized by the semibold title, so selecting a segment never moves its neighbours.
    private func widths() -> [CGFloat] {
        labels.map { ($0 as NSString).size(withAttributes: [.font: font(selected: true)]).width.rounded(.up) + 20 }
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: widths().reduce(0, +) + CGFloat(labels.count - 1) + 2, height: 24)
    }

    /// The segment's x range inside the border.
    private func frames() -> [NSRect] {
        var x: CGFloat = 1
        return widths().map { width in
            defer { x += width + 1 }
            return NSRect(x: x, y: 1, width: width, height: bounds.height - 2)
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        let box = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 6, yRadius: 6)
        theme.color(.backgroundElevated).setFill()
        box.fill()
        NSGraphicsContext.saveGraphicsState()
        box.addClip()
        for (index, frame) in frames().enumerated() {
            let isSelected = index == selectedSegment
            if isSelected {
                theme.color(.selection).setFill()
                frame.fill()
            }
            if index < labels.count - 1 {
                theme.color(.border).setFill()
                NSRect(x: frame.maxX, y: 0, width: 1, height: bounds.height).fill()
            }
            let token: ColorToken = !segmentEnabled[index] ? .textDisabled : isSelected ? .text : .textSecondary
            let title = NSAttributedString(string: labels[index], attributes: [
                .font: font(selected: isSelected), .foregroundColor: theme.color(token),
            ])
            let size = title.size()
            title.draw(at: NSPoint(x: frame.midX - size.width / 2, y: frame.midY - size.height / 2))
        }
        NSGraphicsContext.restoreGraphicsState()
        theme.color(.border).setStroke()
        box.lineWidth = 1
        box.stroke()
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        guard let index = frames().firstIndex(where: { $0.insetBy(dx: -0.5, dy: 0).contains(point) }), segmentEnabled[index] else { return }
        selectedSegment = index
        sendAction(action, to: target)
    }

    override func accessibilityValue() -> Any? { label(forSegment: selectedSegment) }
}

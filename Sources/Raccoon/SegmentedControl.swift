import AppKit
import QuartzCore
import RaccoonDomain

/// The segmented control of design-system.md (§6 Response viewer, Segmented control), in the three
/// looks of `SegmentStyle`. The selected title is `text` semibold, a disabled one `textDisabled`.
/// It answers the parts of NSSegmentedControl the panes use. A click slides the thumb or the
/// underline on a spring; every other change, and every title colour, lands on the same frame
/// (surfaces.md §7, Segment indicator).
final class SegmentedControl: NSControl, NSViewToolTipOwner {
    private let theme: ThemeEnvironment
    private let style: SegmentStyle
    private let reduceMotion: () -> Bool
    /// Where the thumb or underline is, and where it is going. Nil until the first draw with a selection.
    private var motion: IndicatorMotion?
    /// Runs only while a slide is under way.
    private var link: CADisplayLink?
    private var labels: [String]
    /// The "11" of "Headers 11", drawn smaller and dimmer than the title.
    private var counts: [Int?]
    /// SF Symbols drawn in place of the labels, 30 pt segments; the labels become each segment's
    /// tooltip and accessibility label (the inspector's pane switch).
    private let symbols: [String]?
    private var segmentEnabled: [Bool]
    private var hovered: Int? { didSet { if hovered != oldValue { needsDisplay = true } } }
    private var hoverArea: NSTrackingArea?
    var selectedSegment = -1 { didSet { needsDisplay = true } }
    var segmentCount: Int { labels.count }

    init(labels: [String], symbols: [String]? = nil, style: SegmentStyle = .boxed,
         reduceMotion: @escaping () -> Bool = { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }, theme: ThemeEnvironment) {
        self.labels = labels
        counts = Array(repeating: nil, count: labels.count)
        self.symbols = symbols
        self.style = style
        self.reduceMotion = reduceMotion
        self.theme = theme
        segmentEnabled = Array(repeating: true, count: labels.count)
        super.init(frame: .zero)
        setAccessibilityRole(.radioGroup)
        theme.paint(self) { control, _ in control.needsDisplay = true }
        if symbols != nil {
            for index in labels.indices { addToolTip(NSRect(x: 1 + CGFloat(index) * 31, y: 0, width: 30, height: 24), owner: self, userData: nil) }
        }
    }

    func view(_ view: NSView, stringForToolTip tag: NSView.ToolTipTag, point: NSPoint, userData data: UnsafeMutableRawPointer?) -> String {
        layout.index(at: point, height: bounds.height).flatMap { label(forSegment: $0) } ?? ""
    }

    override func accessibilityChildren() -> [Any]? {
        guard symbols != nil else { return super.accessibilityChildren() }
        return frames().enumerated().map { index, frame in
            let element = NSAccessibilityElement.element(
                withRole: .radioButton, frame: NSAccessibility.screenRect(fromView: self, rect: frame), label: label(forSegment: index), parent: self
            ) as! NSAccessibilityElement
            element.setAccessibilityValue(index == selectedSegment)
            element.setAccessibilityEnabled(segmentEnabled[index])
            return element
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// The title, then its count: what a screen reader says.
    func label(forSegment index: Int) -> String? {
        guard labels.indices.contains(index) else { return nil }
        return counts[index].map { "\(labels[index]) \($0)" } ?? labels[index]
    }

    func setCount(_ count: Int?, forSegment index: Int) {
        guard counts.indices.contains(index) else { return }
        counts[index] = count
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

    // MARK: Layout

    /// Sized by the semibold title, so selecting a segment never moves its neighbours.
    private var layout: SegmentLayout {
        let widths: [CGFloat] = labels.indices.map { index in
            symbols != nil ? 10 : titleString(index, selected: true).size().width.rounded(.up)
        }
        return SegmentLayout(style: style, contentWidths: widths)
    }

    private func frames() -> [NSRect] { layout.frames(height: bounds.height) }

    override var intrinsicContentSize: NSSize {
        let height: CGFloat = switch style {
        case .boxed: 24
        case .track: 28
        // The row it sits in sets the height, so the underline lands on the row's rule.
        case .underline: NSView.noIntrinsicMetric
        }
        return NSSize(width: layout.width, height: height)
    }

    // MARK: Drawing

    private func titleToken(_ index: Int, selected: Bool) -> ColorToken {
        !segmentEnabled[index] ? .textDisabled : selected || hovered == index ? .text : .textSecondary
    }

    /// The title and, smaller and dimmer, its count 5 pt after it.
    private func titleString(_ index: Int, selected: Bool) -> NSAttributedString {
        let title = NSMutableAttributedString(string: labels[index], attributes: [
            .font: NSFont.systemFont(ofSize: 12, weight: selected ? .semibold : .regular),
            .foregroundColor: theme.color(titleToken(index, selected: selected)),
        ])
        if let count = counts[index] {
            let token: ColorToken = !segmentEnabled[index] ? .textDisabled : selected ? .textSecondary : .textTertiary
            title.append(NSAttributedString(string: " ", attributes: [.font: NSFont.systemFont(ofSize: 12), .kern: 2]))
            title.append(NSAttributedString(string: "\(count)", attributes: [
                .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular), .foregroundColor: theme.color(token),
            ]))
        }
        return title
    }

    private func drawTitle(_ index: Int, in frame: NSRect) {
        let isSelected = index == selectedSegment
        if let symbols {
            let configuration = NSImage.SymbolConfiguration(pointSize: 12, weight: .regular)
                .applying(.init(paletteColors: [theme.color(titleToken(index, selected: isSelected))]))
            if let image = NSImage(systemSymbolName: symbols[index], accessibilityDescription: labels[index])?.withSymbolConfiguration(configuration) {
                image.draw(in: NSRect(x: frame.midX - image.size.width / 2, y: frame.midY - image.size.height / 2,
                                      width: image.size.width, height: image.size.height),
                           from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
            }
            return
        }
        let title = titleString(index, selected: isSelected)
        let size = title.size()
        title.draw(at: NSPoint(x: frame.midX - size.width / 2, y: frame.midY - size.height / 2))
    }

    override func draw(_ dirtyRect: NSRect) {
        switch style {
        case .boxed: drawBoxed()
        case .track: drawTrack()
        case .underline: drawUnderline()
        }
    }

    /// A 1 pt `border`, 6 pt radius, `backgroundElevated` box of 22 pt segments split by 1 pt rules; the selected one `selection`.
    private func drawBoxed() {
        let box = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 6, yRadius: 6)
        theme.color(.backgroundElevated).setFill()
        box.fill()
        NSGraphicsContext.saveGraphicsState()
        box.addClip()
        for (index, frame) in frames().enumerated() {
            if index == selectedSegment {
                theme.color(.selection).setFill()
                frame.fill()
            }
            if index < labels.count - 1 {
                theme.color(.border).setFill()
                NSRect(x: frame.maxX, y: 0, width: 1, height: bounds.height).fill()
            }
            drawTitle(index, in: frame)
        }
        NSGraphicsContext.restoreGraphicsState()
        theme.color(.border).setStroke()
        box.lineWidth = 1
        box.stroke()
    }

    /// A `selection` track at 60 %, and under the chosen title a thumb: `backgroundElevated`, a hairline and a 1 pt shadow.
    private func drawTrack() {
        theme.color(.selection).withAlphaComponent(0.6).setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 8, yRadius: 8).fill()
        let frames = frames()
        if let thumbFrame = indicatorFrame(in: frames) {
            let thumb = NSBezierPath(roundedRect: thumbFrame, xRadius: 6, yRadius: 6)
            NSGraphicsContext.saveGraphicsState()
            let shadow = NSShadow()
            shadow.shadowColor = NSColor.black.withAlphaComponent(0.14)
            shadow.shadowBlurRadius = 2
            shadow.shadowOffset = NSSize(width: 0, height: -1)
            shadow.set()
            theme.color(.backgroundElevated).setFill()
            thumb.fill()
            NSGraphicsContext.restoreGraphicsState()
            theme.color(.border).withAlphaComponent(0.7).setStroke()
            thumb.lineWidth = 0.5
            thumb.stroke()
        }
        for (index, frame) in frames.enumerated() { drawTitle(index, in: frame) }
    }

    /// Bare titles, and a 2 pt `text` underline along the bottom under the chosen one.
    private func drawUnderline() {
        let frames = frames()
        for (index, frame) in frames.enumerated() { drawTitle(index, in: frame) }
        guard let line = indicatorFrame(in: frames) else { return }
        theme.color(.text).setFill()
        NSBezierPath(roundedRect: NSRect(x: line.minX, y: bounds.height - 2, width: line.width, height: 2), xRadius: 1, yRadius: 1).fill()
    }

    // MARK: Slide

    /// The thumb's or the underline's frame now, or nil with no segment chosen. A target that moved
    /// without a click (a new Response, another Tab, a count that changed a width) is followed at once.
    private func indicatorFrame(in frames: [NSRect]) -> NSRect? {
        guard frames.indices.contains(selectedSegment) else {
            motion = nil
            return nil
        }
        let now = CACurrentMediaTime()
        var current = motion ?? IndicatorMotion(frame: frames[selectedSegment])
        current.follow(frames[selectedSegment], animated: false, at: now)
        motion = current
        return current.frame(at: now)
    }

    /// A click: the title colours change on this frame, the indicator slides from where it is.
    private func choose(_ index: Int) {
        let previous = selectedSegment
        selectedSegment = index
        let frames = frames()
        guard style != .boxed, previous != index, window != nil, !reduceMotion(),
              frames.indices.contains(previous), frames.indices.contains(index) else { return }
        var current = motion ?? IndicatorMotion(frame: frames[previous])
        current.follow(frames[index], animated: true, at: CACurrentMediaTime())
        motion = current
        startLink()
    }

    private func startLink() {
        guard link == nil else { return }
        let link = displayLink(target: self, selector: #selector(advance(_:)))
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    private func stopLink() {
        link?.invalidate()
        link = nil
    }

    @objc private func advance(_ link: CADisplayLink) {
        needsDisplay = true
        guard var current = motion else { return stopLink() }
        guard current.isSettled(at: CACurrentMediaTime()) else { return }
        current.settle()
        motion = current
        stopLink()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        // The link retains this view, so a view that left its window must let go of it.
        if window == nil { stopLink() }
    }

    // MARK: Pointer

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverArea { removeTrackingArea(hoverArea) }
        hoverArea = nil
        // Boxed has no hover state: the Inspector's switch keeps its look.
        guard style != .boxed else { return }
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .mouseMoved, .activeInKeyWindow, .inVisibleRect], owner: self)
        addTrackingArea(area)
        hoverArea = area
    }

    private func updateHover(_ event: NSEvent) {
        hovered = layout.index(at: convert(event.locationInWindow, from: nil), height: bounds.height)
    }

    override func mouseEntered(with event: NSEvent) { updateHover(event) }
    override func mouseMoved(with event: NSEvent) { updateHover(event) }
    override func mouseExited(with event: NSEvent) { hovered = nil }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        guard let index = layout.index(at: point, height: bounds.height), segmentEnabled[index] else { return }
        choose(index)
        sendAction(action, to: target)
    }

    override func accessibilityValue() -> Any? { label(forSegment: selectedSegment) }
}

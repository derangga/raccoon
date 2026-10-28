import AppKit
import RaccoonDomain

/// The Breadcrumb (design-system §6): a 28 pt line between the tab strip and the banner that
/// names where the Tab's Request lives. It takes a Breadcrumb and a `select(path)` closure and
/// reads nothing else; the window derives the Breadcrumb from its index and decides what a
/// selection does. No segment takes keyboard focus, so a click leaves it where it was.
final class BreadcrumbBar: NSView {
    static let height: CGFloat = 28

    private static let side: CGFloat = 12
    private static let gap: CGFloat = 2
    /// An 8 pt chevron with `gap` either side of it.
    private static let separator: CGFloat = 8 + 2 * gap
    /// What a truncated segment keeps: its padding and about two letters.
    private static let minimumWidth: CGFloat = 12 + 20

    private let theme: ThemeEnvironment
    private let select: (String) -> Void
    private var segments: [CrumbView] = []
    private(set) var breadcrumb = Breadcrumb(segments: [])
    private let more: CrumbView
    private var chevrons: [NSRect] = []

    /// The views on show, left to right, "…" among them.
    var visibleCrumbs: [CrumbView] {
        (segments + [more]).filter { !$0.isHidden }.sorted { $0.frame.minX < $1.frame.minX }
    }

    init(theme: ThemeEnvironment, select: @escaping (String) -> Void) {
        self.theme = theme
        self.select = select
        more = CrumbView(title: "…", kind: .more, isLast: false, theme: theme)
        super.init(frame: .zero)
        wantsLayer = true
        layer?.masksToBounds = true
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel("Location")
        more.isHidden = true
        addSubview(more)
        theme.paint(self) { bar, theme in
            bar.layer?.backgroundColor = theme.color(.background).cgColor
            bar.needsDisplay = true
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var isFlipped: Bool { true }
    override var intrinsicContentSize: NSSize { NSSize(width: NSView.noIntrinsicMetric, height: Self.height) }

    func show(_ breadcrumb: Breadcrumb) {
        self.breadcrumb = breadcrumb
        segments.forEach { $0.removeFromSuperview() }
        let last = breadcrumb.segments.count - 1
        segments = breadcrumb.segments.enumerated().map { index, segment in
            let crumb = CrumbView(title: segment.title, kind: segment.target == nil ? .text : .button, isLast: index == last, theme: theme)
            crumb.onClick = { [select] in if let target = segment.target { select(target) } }
            addSubview(crumb)
            return crumb
        }
        needsLayout = true
    }

    override func layout() {
        super.layout()
        let available = bounds.width - 2 * Self.side
        let natural = segments.map(\.naturalWidth)
        let all = segments.map(\.title).joined(separator: " › ")
        let fit = Breadcrumb.fit(widths: natural.map(Double.init), separator: Double(Self.separator),
                                 ellipsis: Double(more.naturalWidth), available: Double(available))
        var row: [(view: CrumbView, width: CGFloat)] = []
        for (index, crumb) in segments.enumerated() {
            if case .collapsed(let hidden) = fit, hidden.contains(index) {
                crumb.isHidden = true
                continue
            }
            if case .collapsed(let hidden) = fit, index == hidden.upperBound { row.append((more, more.naturalWidth)) }
            crumb.isHidden = false
            row.append((crumb, natural[index]))
        }
        more.isHidden = true
        if case .collapsed(let hidden) = fit {
            more.isHidden = false
            more.toolTip = all
            more.setAccessibilityLabel(segments[hidden].map(\.title).joined(separator: " › "))
        }

        // Still too narrow: the last segment end-truncates, then the first (a lone segment is both).
        var overflow = row.reduce(0) { $0 + $1.width } + Self.separator * CGFloat(row.count - 1) - available
        for position in [row.count - 1, 0] where overflow > 0 && row.indices.contains(position) && row[position].view !== more {
            let cut = min(overflow, max(0, row[position].width - Self.minimumWidth))
            row[position].width -= cut
            overflow -= cut
        }

        chevrons = []
        var x = Self.side
        for (position, entry) in row.enumerated() {
            if position > 0 {
                chevrons.append(NSRect(x: x - Self.separator + Self.gap, y: (Self.height - 8) / 2, width: 8, height: 8))
            }
            entry.view.frame = NSRect(x: x, y: (Self.height - CrumbView.height) / 2, width: entry.width, height: CrumbView.height)
            entry.view.toolTip = entry.view === more ? all : entry.width < entry.view.naturalWidth ? entry.view.title : nil
            x += entry.width + Self.separator
        }
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        let configuration = NSImage.SymbolConfiguration(pointSize: 8, weight: .semibold)
            .applying(.init(paletteColors: [theme.color(.textTertiary)]))
        guard let chevron = NSImage(systemSymbolName: "chevron.right", accessibilityDescription: nil)?.withSymbolConfiguration(configuration)
        else { return }
        for rect in chevrons {
            let size = chevron.size
            chevron.draw(in: NSRect(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2, width: size.width, height: size.height),
                         from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        }
    }
}

/// One name in the bar: a button, static text (a Draft's title) or the "…".
final class CrumbView: NSView {
    enum Kind { case button, text, more }

    static let height: CGFloat = 22

    let title: String
    let kind: Kind
    private let isLast: Bool
    private let theme: ThemeEnvironment
    private(set) var isHovered = false
    var onClick: () -> Void = {}

    init(title: String, kind: Kind, isLast: Bool, theme: ThemeEnvironment) {
        self.title = title
        self.kind = kind
        self.isLast = isLast
        self.theme = theme
        super.init(frame: .zero)
        focusRingType = .none
        // A Draft's title is the last segment too.
        setAccessibilityElement(true)
        setAccessibilityRole(kind == .button ? .button : .staticText)
        setAccessibilityLabel(title)
        if kind == .text { setAccessibilityValue(title) }
        if kind == .button { setAccessibilitySelected(isLast) }
        theme.paint(self) { crumb, _ in crumb.needsDisplay = true }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    private var attributes: [NSAttributedString.Key: Any] {
        let style = NSMutableParagraphStyle()
        style.lineBreakMode = .byTruncatingTail
        let strong = isLast || kind == .text
        return [
            .font: NSFont.systemFont(ofSize: 13, weight: strong ? .semibold : .regular),
            .foregroundColor: theme.color(strong || isHovered ? .text : .textSecondary),
            .paragraphStyle: style,
        ]
    }

    var textWidth: CGFloat { ceil((title as NSString).size(withAttributes: attributes).width) }
    /// The width its whole name needs: 6 pt padding either side.
    var naturalWidth: CGFloat { textWidth + 12 }

    override func draw(_ dirtyRect: NSRect) {
        if isHovered {
            theme.color(.rowHover).setFill()
            NSBezierPath(roundedRect: bounds, xRadius: 4, yRadius: 4).fill()
        }
        let text = NSAttributedString(string: title, attributes: attributes)
        let height = text.size().height
        text.draw(in: NSRect(x: 6, y: (bounds.height - height) / 2, width: max(0, bounds.width - 12), height: height))
    }

    // MARK: Hover and click

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
    }

    override func mouseEntered(with event: NSEvent) { setHovered(kind == .button) }
    override func mouseExited(with event: NSEvent) { setHovered(false) }

    private func setHovered(_ hovered: Bool) {
        guard hovered != isHovered else { return }
        isHovered = hovered
        needsDisplay = true
    }

    /// Swallowed, so the click goes no further up the responder chain and takes no focus.
    override func mouseDown(with event: NSEvent) {}

    override func mouseUp(with event: NSEvent) {
        guard kind == .button, bounds.contains(convert(event.locationInWindow, from: nil)) else { return }
        onClick()
    }

    override func accessibilityPerformPress() -> Bool {
        guard kind == .button else { return false }
        onClick()
        return true
    }
}

/// Keeps the bar on the selected Tab's Breadcrumb. It derives it from the window's index by
/// RequestID each time the selected Tab, the Tab list, a Draft's title or the index changes, so
/// a rename or a move shows with the Tab doing nothing. The segments last shown for each
/// Request are kept for the moment the index has no entry for it, and dropped with its Tab.
final class BreadcrumbBinding {
    let bar: BreadcrumbBar
    private let window: WindowModel
    private(set) var lastKnown: [RequestID: Breadcrumb] = [:]

    /// `select` is what a click on a segment does with its path.
    init(window: WindowModel, theme: ThemeEnvironment, select: @escaping (String) -> Void) {
        self.window = window
        bar = BreadcrumbBar(theme: theme, select: select)
        update()
    }

    private func update() {
        let (source, title, index, open) = withObservationTracking {
            let tab = window.selectedTab?.tab
            return (tab?.source ?? .draft, tab.map(window.name(of:)) ?? "Draft", window.index,
                    Set(window.tabs.compactMap { tab -> RequestID? in if case .request(let id) = tab.tab.source { id } else { nil } }))
        } onChange: { [weak self] in
            Task { @MainActor in self?.update() }
        }
        lastKnown = lastKnown.filter { open.contains($0.key) }
        var known: Breadcrumb?
        if case .request(let id) = source { known = lastKnown[id] }
        let breadcrumb = Breadcrumb.of(source: source, title: title, index: index, lastKnown: known)
        if case .request(let id) = source, index.path(of: id) != nil { lastKnown[id] = breadcrumb }
        if breadcrumb != bar.breadcrumb { bar.show(breadcrumb) }
    }
}

import AppKit
import RaccoonDomain

/// The trigger of a Dropdown (design-system §6 Dropdown): a themed button showing the chosen
/// option's title, which opens a themed list under itself. It shows and reports; the owner decides.
class Dropdown: NSControl {
    static let font = NSFont.systemFont(ofSize: 12)
    /// Leading inset, gap between the title and the chevron, and the chevron with its trailing inset.
    static let lead: CGFloat = 8, gap: CGFloat = 8, chevron: CGFloat = 18

    let theme: ThemeEnvironment
    private let height: CGFloat
    /// The widest the trigger gets; the list is not held to it.
    var maxWidth: CGFloat = .greatestFiniteMagnitude
    var entries: [DropdownEntry] = [] {
        didSet {
            guard oldValue != entries else { return }
            needsDisplay = true
            setAccessibilityValue(title)
        }
    }
    var onPick: (DropdownPick) -> Void = { _ in }
    private var isHovered = false { didSet { needsDisplay = true } }
    private var hasFocus = false { didSet { needsDisplay = true } }

    var title: String { DropdownEntry.title(of: entries) }

    /// The title's width plus the insets, to `maxWidth`.
    var fittingWidth: CGFloat {
        min(maxWidth, ceil(title.size(withAttributes: [.font: Self.font]).width) + 2 + Self.lead + Self.gap + Self.chevron)
    }

    init(label: String, theme: ThemeEnvironment, height: CGFloat) {
        self.theme = theme
        self.height = height
        super.init(frame: .zero)
        setAccessibilityRole(.popUpButton)
        setAccessibilityLabel(label)
        translatesAutoresizingMaskIntoConstraints = false
        heightAnchor.constraint(equalToConstant: height).isActive = true
        theme.paint(self) { control, _ in control.needsDisplay = true }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var intrinsicContentSize: NSSize { NSSize(width: NSView.noIntrinsicMetric, height: height) }

    override func becomeFirstResponder() -> Bool {
        hasFocus = true
        return super.becomeFirstResponder()
    }

    override func resignFirstResponder() -> Bool {
        hasFocus = false
        DropdownPanel.shared.hide(ifOwnedBy: self)
        return super.resignFirstResponder()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self))
    }

    override func mouseEntered(with event: NSEvent) { isHovered = true }
    override func mouseExited(with event: NSEvent) { isHovered = false }

    override func draw(_ dirtyRect: NSRect) {
        let box = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 6, yRadius: 6)
        theme.color(isHovered || isOpen ? .rowHover : .backgroundElevated).setFill()
        box.fill()
        theme.color(.border).setStroke()
        box.lineWidth = 1
        box.stroke()

        let style = NSMutableParagraphStyle()
        style.lineBreakMode = .byTruncatingTail
        let text = NSAttributedString(string: title, attributes: [.font: Self.font, .foregroundColor: theme.color(.text), .paragraphStyle: style])
        let textHeight = text.size().height
        text.draw(in: NSRect(x: Self.lead, y: bounds.midY - textHeight / 2,
                             width: max(0, bounds.width - Self.lead - Self.gap - Self.chevron), height: textHeight))

        let configuration = NSImage.SymbolConfiguration(pointSize: 9, weight: .semibold)
            .applying(.init(paletteColors: [theme.color(.textSecondary)]))
        if let image = NSImage(systemSymbolName: "chevron.down", accessibilityDescription: nil)?.withSymbolConfiguration(configuration) {
            image.draw(in: NSRect(x: bounds.maxX - 8 - image.size.width, y: bounds.midY - image.size.height / 2,
                                  width: image.size.width, height: image.size.height),
                       from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        }

        if hasFocus {
            let ring = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 5, yRadius: 5)
            theme.color(.focusRing).setStroke()
            ring.lineWidth = 2
            ring.stroke()
        }
    }

    var isOpen: Bool { DropdownPanel.shared.isShown(for: self) }

    /// Click, Space, Return, ↓, ⌃E and VoiceOver's press all come through here. Opening an open list closes it.
    func open() {
        guard isEnabled, !entries.isEmpty, window != nil else { return }
        if isOpen { return close() }
        window?.makeFirstResponder(self)
        DropdownPanel.shared.show(for: self)
        needsDisplay = true
    }

    func close() {
        DropdownPanel.shared.hide(ifOwnedBy: self)
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) { open() }

    override func accessibilityPerformPress() -> Bool {
        open()
        return true
    }

    /// ↑ ↓ Return Space Esc go to the list while it is open; Space, Return and ↓ open it.
    override func keyDown(with event: NSEvent) {
        let panel = DropdownPanel.shared
        switch (event.keyCode, isOpen) {
        case (125, true): panel.move(.down)
        case (126, true): panel.move(.up)
        case (36, true), (76, true), (49, true): panel.pickHighlighted()
        case (53, true): close()
        case (48, true):
            close()
            super.keyDown(with: event)
        case (36, false), (76, false), (49, false), (125, false): open()
        default: super.keyDown(with: event)
        }
    }
}

/// The one list window: a borderless panel that cannot become key, a child of the window the
/// trigger is in, so the keyboard stays on the trigger. Rows take the pointer.
final class DropdownPanel {
    static let shared = DropdownPanel()

    static let padding: CGFloat = 4
    static let maxRows: CGFloat = 8
    static let maxWidth: CGFloat = 320
    /// Clear space round the list inside its window, where its soft shadow falls.
    static let margin: CGFloat = 20

    private var window: DropdownWindow?
    private let rows = DropdownRows()
    private weak var owner: Dropdown?
    private var monitor: Any?
    private var resignObserver: Any?

    func isShown(for dropdown: Dropdown) -> Bool { owner === dropdown && (window?.isVisible ?? false) }
    var isShown: Bool { window?.isVisible ?? false }
    var frame: NSRect? { window?.frame }
    var highlighted: Int? { rows.list.highlighted }

    /// Below the trigger, above it where the screen ends, hanging from the trigger's window.
    func show(for dropdown: Dropdown) {
        guard let parent = dropdown.window else { return }
        owner = dropdown
        let theme = dropdown.theme
        rows.theme = theme
        rows.list = DropdownList(entries: dropdown.entries)
        rows.onPick = { [weak self] index in
            self?.rows.list.highlight(index)
            self?.pickHighlighted()
        }

        let inner = min(max(rows.idealWidth + 2 * Self.padding, dropdown.bounds.width), Self.maxWidth) - 2 * Self.padding
        let total = rows.layout(width: inner)
        let visible = min(total, Self.maxRows * DropdownRows.optionHeight)
        let size = NSSize(width: inner + 2 * Self.padding, height: visible + 2 * Self.padding)

        let margin = Self.margin
        let windowSize = NSSize(width: size.width + 2 * margin, height: size.height + 2 * margin)
        let container = NSView(frame: NSRect(origin: .zero, size: windowSize))
        let box = NSView(frame: NSRect(x: margin, y: margin, width: size.width, height: size.height))
        box.wantsLayer = true
        box.layer?.cornerRadius = 8
        box.layer?.borderWidth = 1
        box.layer?.borderColor = theme.color(.border).withAlphaComponent(0.5).cgColor
        box.layer?.backgroundColor = theme.color(.backgroundElevated).cgColor
        box.layer?.shadowColor = NSColor.black.cgColor
        box.layer?.shadowOpacity = 0.12
        box.layer?.shadowRadius = 12
        box.layer?.shadowOffset = CGSize(width: 0, height: -4)
        container.addSubview(box)
        let scroll = NSScrollView(frame: NSRect(x: Self.padding, y: Self.padding, width: inner, height: visible))
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = total > visible
        scroll.scrollerStyle = .overlay
        rows.frame = NSRect(x: 0, y: 0, width: inner, height: total)
        scroll.documentView = rows
        box.addSubview(scroll)
        let window = window ?? DropdownWindow()
        self.window = window
        window.contentView = container
        rows.scrollToHighlighted()

        let trigger = parent.convertToScreen(dropdown.convert(dropdown.bounds, to: nil))
        var origin = NSPoint(x: trigger.minX, y: trigger.minY - 4 - size.height)
        if let screen = parent.screen?.visibleFrame {
            if origin.y < screen.minY { origin.y = trigger.maxY + 4 }
            origin.x = min(max(origin.x, screen.minX), screen.maxX - size.width)
        }
        window.setFrame(NSRect(origin: NSPoint(x: origin.x - margin, y: origin.y - margin), size: windowSize), display: true)
        if window.parent !== parent {
            window.parent?.removeChildWindow(window)
            parent.addChildWindow(window, ordered: .above)
        }
        window.orderFront(nil)
        observeDismissal(parent: parent)
    }

    /// A press outside the list (but not on the trigger, which toggles), a scroll outside it, a ⌘
    /// key, and the window losing key all close it.
    private func observeDismissal(parent: NSWindow) {
        if monitor == nil {
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown, .scrollWheel, .keyDown]) { [weak self] event in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    let closes = switch event.type {
                    case .keyDown: event.modifierFlags.contains(.command)
                    default: event.window !== self.window && !self.isOnTrigger(event)
                    }
                    if closes { self.hide() }
                }
                return event
            }
        }
        if resignObserver == nil {
            resignObserver = NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification, object: parent, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.hide() }
            }
        }
    }

    private func isOnTrigger(_ event: NSEvent) -> Bool {
        guard let owner, event.window === owner.window else { return false }
        return owner.bounds.contains(owner.convert(event.locationInWindow, from: nil))
    }

    func move(_ step: DropdownList.Step) {
        rows.list.move(step)
        rows.scrollToHighlighted()
    }

    /// Closes first, then reports, so the owner may open another list from its reaction.
    func pickHighlighted() {
        guard let pick = rows.list.pick() else { return }
        let owner = owner
        hide()
        owner?.onPick(pick)
    }

    func hide(ifOwnedBy dropdown: Dropdown) {
        if owner === dropdown { hide() }
    }

    func hide() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        if let resignObserver { NotificationCenter.default.removeObserver(resignObserver) }
        resignObserver = nil
        let closing = owner
        owner = nil
        if let window {
            window.parent?.removeChildWindow(window)
            window.orderOut(nil)
        }
        closing?.needsDisplay = true
    }
}

/// The rows, drawn: the chosen option's check in `accent`, titles in 12 pt `text`, a detail line
/// in 11 pt `textTertiary`, the highlighted row on `rowHover`.
private final class DropdownRows: NSView {
    static let optionHeight: CGFloat = 28, detailHeight: CGFloat = 40, separatorHeight: CGFloat = 9
    private static let column: CGFloat = 24, trailing: CGFloat = 12
    private static let titleFont = NSFont.systemFont(ofSize: 12), detailFont = NSFont.systemFont(ofSize: 11)

    var theme: ThemeEnvironment?
    var list = DropdownList(entries: []) {
        didSet {
            if oldValue.highlighted != list.highlighted { needsDisplay = true }
        }
    }
    var onPick: (Int) -> Void = { _ in }
    private var frames: [NSRect] = []

    override var isFlipped: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    init() {
        super.init(frame: .zero)
        setAccessibilityRole(.menu)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    private func height(of entry: DropdownEntry) -> CGFloat {
        switch entry {
        case .separator: Self.separatorHeight
        case let .option(_, _, detail, _): detail == nil ? Self.optionHeight : Self.detailHeight
        case .action: Self.optionHeight
        }
    }

    /// Stacks the rows at `width`, and answers their total height.
    func layout(width: CGFloat) -> CGFloat {
        var y: CGFloat = 0
        frames = list.entries.map { entry in
            defer { y += height(of: entry) }
            return NSRect(x: 0, y: y, width: width, height: height(of: entry))
        }
        return y
    }

    var idealWidth: CGFloat {
        let widest = list.entries.map { entry -> CGFloat in
            switch entry {
            case let .option(_, title, detail, _):
                max(Self.width(title, Self.titleFont), detail.map { Self.width($0, Self.detailFont) } ?? 0)
            case let .action(_, title): Self.width(title, Self.titleFont)
            case .separator: 0
            }
        }.max() ?? 0
        return ceil(widest) + Self.column + Self.trailing
    }

    private static func width(_ text: String, _ font: NSFont) -> CGFloat { (text as NSString).size(withAttributes: [.font: font]).width }

    func scrollToHighlighted() {
        if let index = list.highlighted, frames.indices.contains(index) { scrollToVisible(frames[index]) }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseMoved, .activeAlways, .inVisibleRect], owner: self))
    }

    private func row(at event: NSEvent) -> Int? {
        let point = convert(event.locationInWindow, from: nil)
        return frames.firstIndex { $0.contains(point) }
    }

    override func mouseMoved(with event: NSEvent) {
        if let index = row(at: event) { list.highlight(index) }
    }

    override func mouseDown(with event: NSEvent) {
        if let index = row(at: event) { onPick(index) }
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let theme else { return }
        for (index, entry) in list.entries.enumerated() where frames.indices.contains(index) && frames[index].intersects(dirtyRect) {
            let box = frames[index]
            if case .separator = entry {
                theme.color(.border).withAlphaComponent(0.5).setFill()
                NSRect(x: 8, y: box.midY - 0.5, width: box.width - 16, height: 1).fill()
                continue
            }
            if index == list.highlighted {
                theme.color(.rowHover).setFill()
                NSBezierPath(roundedRect: box, xRadius: 6, yRadius: 6).fill()
            }
            let style = NSMutableParagraphStyle()
            style.lineBreakMode = .byTruncatingTail
            let textWidth = max(0, box.width - Self.column - Self.trailing)
            func draw(_ text: String, _ font: NSFont, _ token: ColorToken, centeredAt y: CGFloat) {
                let string = NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: theme.color(token), .paragraphStyle: style])
                let lineHeight = string.size().height
                string.draw(in: NSRect(x: box.minX + Self.column, y: y - lineHeight / 2, width: textWidth, height: lineHeight))
            }
            switch entry {
            case let .option(_, title, detail, isChosen):
                if let detail {
                    draw(title, Self.titleFont, .text, centeredAt: box.minY + 13)
                    draw(detail, Self.detailFont, .textTertiary, centeredAt: box.minY + 28)
                } else {
                    draw(title, Self.titleFont, .text, centeredAt: box.midY)
                }
                if isChosen { drawCheck(in: box, theme: theme, centeredAt: detail == nil ? box.midY : box.minY + 13) }
            case let .action(_, title):
                draw(title, Self.titleFont, .text, centeredAt: box.midY)
            case .separator:
                break
            }
        }
    }

    private func drawCheck(in box: NSRect, theme: ThemeEnvironment, centeredAt y: CGFloat) {
        let configuration = NSImage.SymbolConfiguration(pointSize: 11, weight: .medium)
            .applying(.init(paletteColors: [theme.color(.accent)]))
        guard let image = NSImage(systemSymbolName: "checkmark", accessibilityDescription: nil)?.withSymbolConfiguration(configuration) else { return }
        image.draw(in: NSRect(x: box.minX + (Self.column - image.size.width) / 2, y: y - image.size.height / 2,
                              width: image.size.width, height: image.size.height),
                   from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
    }

    override func accessibilityChildren() -> [Any]? {
        list.entries.enumerated().compactMap { index, entry -> Any? in
            guard frames.indices.contains(index) else { return nil }
            let (label, chosen): (String, Bool)
            switch entry {
            case let .option(_, title, _, isChosen): (label, chosen) = (title, isChosen)
            case let .action(_, title): (label, chosen) = (title, false)
            case .separator: return nil
            }
            let element = RowElement()
            element.setAccessibilityRole(.menuItem)
            element.setAccessibilityLabel(label)
            element.setAccessibilityParent(self)
            element.setAccessibilityFrameInParentSpace(frames[index])
            element.setAccessibilitySelected(chosen)
            element.press = { [weak self] in self?.onPick(index) }
            return element
        }
    }

    /// VoiceOver's press on a row; the system calls it on the main thread.
    private nonisolated final class RowElement: NSAccessibilityElement {
        nonisolated(unsafe) var press: @MainActor () -> Void = {}
        override func accessibilityPerformPress() -> Bool {
            let press = press
            MainActor.assumeIsolated { press() }
            return true
        }
    }
}

private final class DropdownWindow: NSPanel {
    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        hidesOnDeactivate = true
        isReleasedWhenClosed = false
        becomesKeyOnlyIfNeeded = true
        acceptsMouseMovedEvents = true
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

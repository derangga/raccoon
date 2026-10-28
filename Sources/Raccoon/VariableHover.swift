import AppKit
import RaccoonDomain

/// The text of a field or text view as TextKit 1 lays it out, and the view whose coordinates
/// `origin` (the text container's) and the pointer are in. Flipped, as text views are.
struct TextLayout {
    let storage: NSTextStorage
    let manager: NSLayoutManager
    let origin: NSPoint
    let space: NSView
}

/// Hover over `{{name}}` in a field that takes Variables (design-system §6 Variable popover).
/// One per field or text view; they share one panel.
final class VariableHover {
    private let panel: VariableTooltipPanel
    private let layout: () -> TextLayout?
    private let kinds: () -> VariableKinds?
    private let theme: () -> ThemeEnvironment?
    /// How long the pointer rests on a token before the popover appears: the system's.
    var delay: TimeInterval
    private var over: VariableToken?
    private var timer: Timer?
    private var pending: (() -> Void)?

    init(
        panel: VariableTooltipPanel = .shared,
        delay: TimeInterval = VariableHover.systemDelay,
        layout: @escaping () -> TextLayout?,
        kinds: @escaping () -> VariableKinds?,
        theme: @escaping () -> ThemeEnvironment?
    ) {
        self.panel = panel
        self.delay = delay
        self.layout = layout
        self.kinds = kinds
        self.theme = theme
    }

    /// AppKit's own tooltip delay, in seconds.
    static var systemDelay: TimeInterval {
        (UserDefaults.standard.object(forKey: "NSInitialToolTipDelay") as? Double ?? 1000) / 1000
    }

    /// The pointer is at `windowPoint`. Over another token while one is shown: that token's
    /// popover, at once. Over none: nothing.
    func pointerMoved(to windowPoint: NSPoint) {
        guard let layout = layout(), let kinds = kinds(), let theme = theme(), let window = layout.space.window,
              let hit = Self.hit(layout.space.convert(windowPoint, from: nil), in: layout)
        else { return exited() }
        guard hit.token != over else { return }
        timer?.invalidate()
        over = hit.token
        let screenRect = window.convertToScreen(layout.space.convert(hit.rect, to: nil))
        pending = { [panel] in panel.show(kinds.tooltip(for: hit.token.name), theme: theme, near: screenRect, in: window) }
        if panel.isShown || delay <= 0 {
            pending?()
        } else {
            timer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in MainActor.assumeIsolated { self?.pending?() } }
        }
    }

    /// The pointer left the token or the view. Closes only what this hover opened, after the
    /// panel's grace, so the pointer can cross into the popover.
    func exited() {
        guard over != nil else { return }
        timer?.invalidate()
        timer = nil
        pending = nil
        over = nil
        panel.hideUnlessPointed()
    }

    /// The token under `point` (in `layout.space`) and the line rectangle it is under there.
    static func hit(_ point: NSPoint, in layout: TextLayout) -> (token: VariableToken, rect: NSRect)? {
        let manager = layout.manager
        guard let container = manager.textContainers.first else { return nil }
        let local = NSPoint(x: point.x - layout.origin.x, y: point.y - layout.origin.y)
        let text = layout.storage.string as NSString
        guard text.length > 0 else { return nil }
        let index = manager.characterIndexForGlyph(at: manager.glyphIndex(for: local, in: container, fractionOfDistanceThroughGlyph: nil))
        // shortcut: only the 512 units either side are scanned, so a hover costs the same in a
        // 5 MB body; a token longer than that is not found. Raise it if names grow.
        let start = max(0, index - 512)
        let nearby = text.substring(with: NSRange(location: start, length: min(text.length, index + 512) - start))
        for found in VariableTokens.ranges(nearby) {
            let range = NSRange(location: found.range.location + start, length: found.range.length)
            guard NSLocationInRange(index, range) else { continue }
            let glyphs = manager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            var line: NSRect?
            manager.enumerateLineFragments(forGlyphRange: glyphs) { _, _, _, lineGlyphs, stop in
                let box = manager.boundingRect(forGlyphRange: NSIntersectionRange(glyphs, lineGlyphs), in: container)
                    .offsetBy(dx: layout.origin.x, dy: layout.origin.y)
                if box.contains(point) { line = box; stop.pointee = true }
            }
            return line.map { (VariableToken(range: range, name: found.name), $0) }
        }
        return nil
    }
}

/// The one popover window. A borderless panel, a child of the window it hangs from, that takes
/// the pointer (to scroll or select the value, or follow the link) but becomes key only once
/// its value is clicked, so showing it changes neither the key window nor any first responder.
final class VariableTooltipPanel {
    static let shared = VariableTooltipPanel()

    static let width: CGFloat = 320

    /// "Variables in request": set once at the composition root.
    var onReveal: ((VariableName) -> Void)?

    private let grace: TimeInterval
    private let pointer: () -> NSPoint
    private var window: TooltipWindow?
    private(set) var view: VariablePopoverView?
    private(set) var monitor: Any?
    private var hideTimer: Timer?
    var isShown: Bool { window?.isVisible ?? false }

    /// `grace` is how long the popover waits, once the pointer leaves its token, for the pointer
    /// to reach it; `pointer` is where the pointer is, in screen coordinates.
    init(grace: TimeInterval = 0.3, pointer: @escaping () -> NSPoint = { NSEvent.mouseLocation }) {
        self.grace = grace
        self.pointer = pointer
    }

    static func content(_ tooltip: VariableTooltip, theme: ThemeEnvironment) -> VariablePopoverView {
        VariablePopoverView(tooltip, theme: theme)
    }

    /// Below `rect` (in screen coordinates), above it where the screen ends, hanging from `parent`.
    /// Closes on a key, click or scroll outside it, for as long as it is shown.
    func show(_ tooltip: VariableTooltip, theme: ThemeEnvironment, near rect: NSRect, in parent: NSWindow) {
        hideTimer?.invalidate()
        let content = Self.content(tooltip, theme: theme)
        content.link.target = self
        content.link.action = #selector(reveal)
        content.onPointerLeft = { [weak self] in self?.pointerLeft() }
        view = content
        let size = content.frame.size
        let window = window ?? TooltipWindow()
        self.window = window
        window.contentView = content

        var origin = NSPoint(x: rect.minX, y: rect.minY - 4 - size.height)
        if let screen = parent.screen?.visibleFrame {
            if origin.y < screen.minY { origin.y = rect.maxY + 4 }
            origin.x = min(max(origin.x, screen.minX), screen.maxX - size.width)
        }
        window.setFrame(NSRect(origin: origin, size: size), display: true)
        if window.parent !== parent {
            window.parent?.removeChildWindow(window)
            parent.addChildWindow(window, ordered: .above)
        }
        window.orderFront(nil)
        if monitor == nil {
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .leftMouseDown, .rightMouseDown, .scrollWheel]) { [weak self] event in
                MainActor.assumeIsolated {
                    guard let self, self.closes(event) else { return }
                    self.hide()
                }
                return event
            }
        }
    }

    /// Whether `event` closes the popover: anything outside it, and inside it any key but a
    /// ⌘ shortcut (⌘C copies the selected value).
    func closes(_ event: NSEvent) -> Bool {
        guard let window, event.windowNumber == window.windowNumber else { return true }
        return event.type == .keyDown && !event.modifierFlags.contains(.command)
    }

    var windowNumber: Int? { window?.windowNumber }

    /// The pointer left the token: close after the grace unless it is over the popover by then.
    func hideUnlessPointed() {
        hideTimer?.invalidate()
        guard grace > 0 else { return hideIfAway() }
        hideTimer = Timer.scheduledTimer(withTimeInterval: grace, repeats: false) { [weak self] _ in MainActor.assumeIsolated { self?.hideIfAway() } }
    }

    private func hideIfAway() {
        guard let frame = window?.frame, !frame.contains(pointer()) else { return }
        hide()
    }

    /// The pointer left the popover.
    func pointerLeft() { hide() }

    @objc private func reveal() {
        guard let name = view?.name else { return }
        hide()
        onReveal?(name)
    }

    func hide() {
        hideTimer?.invalidate()
        hideTimer = nil
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        guard let window else { return }
        let parent = window.parent
        let wasKey = window.isKeyWindow
        parent?.removeChildWindow(window)
        window.orderOut(nil)
        // Clicking the value made the popover key; the window it hung from gets it back.
        if wasKey { parent?.makeKey() }
    }

    var frame: NSRect? { window?.frame }
}

private final class TooltipWindow: NSPanel {
    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        becomesKeyOnlyIfNeeded = true
    }

    /// Only when the value is clicked: its text view needs a key panel to select and copy.
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// The popover's content: the value in a box five lines tall at most, "Secret" or
/// why the name is undefined; then the source chip, the source and "Variables in request →".
final class VariablePopoverView: NSView {
    private static let padding: CGFloat = 8
    private static let lineHeight: CGFloat = 16
    private static let maxLines: CGFloat = 5
    private static let boxInset = NSSize(width: 6, height: 4)

    let name: VariableName
    private(set) var valueBox: NSScrollView?
    private(set) var valueText: NSTextView?
    private(set) var message: NSTextField?
    private(set) var chip: NSTextField?
    private(set) var source: NSTextField?
    let link: NSButton
    var onPointerLeft: (() -> Void)?

    init(_ tooltip: VariableTooltip, theme: ThemeEnvironment) {
        name = tooltip.name
        link = LinkButton(title: "Variables in request →", theme: theme)
        let width = VariableTooltipPanel.width
        let inner = width - 2 * Self.padding
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: 0))
        wantsLayer = true
        layer?.cornerRadius = 6
        layer?.borderWidth = 1
        layer?.borderColor = theme.color(.border).cgColor
        layer?.backgroundColor = theme.color(.backgroundElevated).cgColor

        // Not flipped: laid out bottom up, footer first.
        let footerHeight: CGFloat = 20
        var y = Self.padding
        link.sizeToFit()
        link.frame = NSRect(x: width - Self.padding - link.frame.width, y: y + (footerHeight - link.frame.height) / 2,
                            width: link.frame.width, height: link.frame.height)
        addSubview(link)
        if let from = tooltip.source {
            let chip = NSTextField(labelWithString: from == "Globals" ? "G" : "E")
            chip.font = .systemFont(ofSize: 10, weight: .bold)
            chip.textColor = theme.color(.text)
            chip.alignment = .center
            chip.wantsLayer = true
            chip.layer?.cornerRadius = 4
            chip.layer?.backgroundColor = theme.color(.selection).cgColor
            chip.frame = NSRect(x: Self.padding, y: y + 2, width: 16, height: 16)
            let source = NSTextField(labelWithString: from)
            source.font = .systemFont(ofSize: 11)
            source.textColor = theme.color(.textTertiary)
            source.lineBreakMode = .byTruncatingTail
            source.sizeToFit()
            source.frame = NSRect(x: chip.frame.maxX + 6, y: y + (footerHeight - source.frame.height) / 2,
                                  width: min(source.frame.width, link.frame.minX - 8 - chip.frame.maxX - 6), height: source.frame.height)
            addSubview(chip)
            addSubview(source)
            self.chip = chip
            self.source = source
        }
        y += footerHeight + 6

        let body: NSView
        switch tooltip {
        case .defined(_, _, let value):
            let box = Self.box(value, width: inner, fill: .backgroundRecessed, theme: theme)
            valueBox = box
            valueText = box.documentView as? NSTextView
            body = box
        case .secret:
            let label = NSTextField(labelWithString: "Secret")
            label.font = .systemFont(ofSize: 11)
            label.textColor = theme.color(.variableSecret)
            let lock = NSImageView(image: NSImage(systemSymbolName: "lock.fill", accessibilityDescription: nil)!)
            lock.symbolConfiguration = .init(pointSize: 10, weight: .regular)
            lock.contentTintColor = theme.color(.variableSecret)
            let row = NSStackView(views: [lock, label])
            row.spacing = 4
            row.frame.size = row.fittingSize
            message = label
            body = row
        case .undefined:
            let label = NSTextField(wrappingLabelWithString: tooltip.detail)
            label.font = .systemFont(ofSize: 11)
            label.textColor = theme.color(.variableUndefined)
            let needed = label.cell!.cellSize(forBounds: NSRect(x: 0, y: 0, width: inner, height: .greatestFiniteMagnitude))
            label.frame.size = NSSize(width: inner, height: ceil(needed.height))
            message = label
            body = label
        }
        body.frame.origin = NSPoint(x: Self.padding, y: y)
        addSubview(body)
        frame.size.height = y + body.frame.height + Self.padding
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// The value in SF Mono 11 / 16, wrapping at any character as a token or a JWT has no break
    /// to wrap at, as tall as it needs up to five lines, then scrolling. Selectable, not editable.
    /// The inspector's selected row shows the same box on `background`.
    static func box(_ value: String, width: CGFloat, fill: ColorToken, theme: ThemeEnvironment) -> NSScrollView {
        let style = NSMutableParagraphStyle()
        style.lineBreakMode = .byCharWrapping
        style.minimumLineHeight = lineHeight
        style.maximumLineHeight = lineHeight
        let text = NSTextView(frame: NSRect(x: 0, y: 0, width: width - 2, height: 0))
        text.isEditable = false
        text.isSelectable = true
        text.isRichText = false
        text.textContainerInset = boxInset
        text.textContainer?.lineFragmentPadding = 0
        text.textContainer?.widthTracksTextView = true
        text.isVerticallyResizable = true
        text.autoresizingMask = [.width]
        text.backgroundColor = theme.color(fill)
        text.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        text.textStorage?.setAttributedString(NSAttributedString(string: value, attributes: [
            .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .regular), .foregroundColor: theme.color(.text), .paragraphStyle: style,
        ]))
        text.layoutManager?.ensureLayout(for: text.textContainer!)
        let used = ceil(text.layoutManager?.usedRect(for: text.textContainer!).height ?? lineHeight)
        text.frame.size.height = used + 2 * boxInset.height

        let box = NSScrollView(frame: NSRect(x: 0, y: 0, width: width, height: min(used, maxLines * lineHeight) + 2 * boxInset.height + 2))
        box.documentView = text
        box.hasVerticalScroller = true
        box.autohidesScrollers = true
        box.drawsBackground = false
        box.contentInsets = NSEdgeInsets(top: 1, left: 1, bottom: 1, right: 1)
        box.automaticallyAdjustsContentInsets = false
        box.wantsLayer = true
        box.layer?.cornerRadius = 4
        box.layer?.borderWidth = 1
        box.layer?.borderColor = theme.color(.border).cgColor
        box.layer?.backgroundColor = theme.color(fill).cgColor
        return box
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
    }

    override func mouseExited(with event: NSEvent) {
        onPointerLeft?()
    }
}

/// An 11 pt `accent` text button, underlined while the pointer is over it.
private final class LinkButton: NSButton {
    private let theme: ThemeEnvironment

    init(title: String, theme: ThemeEnvironment) {
        self.theme = theme
        super.init(frame: .zero)
        self.title = title
        isBordered = false
        setButtonType(.momentaryChange)
        style(underlined: false)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    private func style(underlined: Bool) {
        attributedTitle = NSAttributedString(string: title, attributes: [
            .font: NSFont.systemFont(ofSize: 11), .foregroundColor: theme.color(.accent),
            .underlineStyle: underlined ? NSUnderlineStyle.single.rawValue : 0,
        ])
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
    }

    override func mouseEntered(with event: NSEvent) { style(underlined: true) }
    override func mouseExited(with event: NSEvent) { style(underlined: false) }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .pointingHand) }
}

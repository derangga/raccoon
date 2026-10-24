import AppKit
import RaccoonDomain

/// A text view that takes Variables: typing `{{` in it offers the names in scope. The raw body
/// and the field editor of every VariableField are one.
class VariableTextView: NSTextView {
    var suggestions: VariableSuggestions?

    override func didChangeText() {
        super.didChangeText()
        suggestions?.textChanged(in: self)
    }

    override func setSelectedRanges(_ ranges: [NSValue], affinity: NSSelectionAffinity, stillSelecting: Bool) {
        super.setSelectedRanges(ranges, affinity: affinity, stillSelecting: stillSelecting)
        suggestions?.selectionChanged(in: self)
    }

    /// ↑ ↓ Return Tab Esc go to the list while it is open, and keep their meaning otherwise.
    override func doCommand(by selector: Selector) {
        if suggestions?.handle(selector, in: self) == true { return }
        super.doCommand(by: selector)
    }

    override func resignFirstResponder() -> Bool {
        let resigned = super.resignFirstResponder()
        if resigned { suggestions?.close() }
        return resigned
    }
}

/// The Variable suggestions of one field or text view (design-system §6). They share one panel.
final class VariableSuggestions {
    private let panel: VariableSuggestionPanel
    private let kinds: () -> VariableKinds?
    private let theme: () -> ThemeEnvironment?
    private(set) var items: [VariableSuggestion] = []
    private(set) var selected = 0
    private var query: VariableCompletion.Query?

    init(panel: VariableSuggestionPanel = .shared, kinds: @escaping () -> VariableKinds?, theme: @escaping () -> ThemeEnvironment?) {
        self.panel = panel
        self.kinds = kinds
        self.theme = theme
    }

    var isOpen: Bool { panel.owner === self && panel.isShown }

    /// Typing opens the list, or refilters it.
    func textChanged(in view: NSTextView) { refresh(in: view) }

    /// A caret move only refilters or closes an open list; it never opens one.
    func selectionChanged(in view: NSTextView) {
        if isOpen { refresh(in: view) }
    }

    private func refresh(in view: NSTextView) {
        let caret = view.selectedRange()
        guard caret.length == 0, let kinds = kinds(), let theme = theme(), let window = view.window,
              let query = VariableCompletion.query(in: view.string, caret: caret.location)
        else { return close() }
        let items = kinds.suggestions(matching: query.prefix)
        guard !items.isEmpty else { return close() }
        let kept = isOpen ? self.items[safe: selected].flatMap { old in items.firstIndex { $0.name == old.name } } : nil
        self.query = query
        self.items = items
        selected = kept ?? 0
        // Anchored where the name starts, so the list does not drift while typing.
        let anchor = view.firstRect(forCharacterRange: NSRange(location: query.range.location, length: 0), actualRange: nil)
        VariableTooltipPanel.shared.hide()
        panel.show(items, selected: selected, theme: theme, near: anchor, in: window, owner: self) { [weak self, weak view] index in
            if let view { self?.accept(index, in: view) }
        }
    }

    /// True when the list took the command.
    func handle(_ selector: Selector, in view: NSTextView) -> Bool {
        guard isOpen else { return false }
        switch selector {
        case #selector(NSResponder.moveDown(_:)): move(to: min(selected + 1, items.count - 1))
        case #selector(NSResponder.moveUp(_:)): move(to: max(selected - 1, 0))
        case #selector(NSResponder.insertNewline(_:)), #selector(NSResponder.insertTab(_:)): accept(selected, in: view)
        case #selector(NSResponder.cancelOperation(_:)): close()
        default: return false
        }
        return true
    }

    private func move(to index: Int) {
        selected = index
        panel.select(index)
    }

    /// Writes `name}}` in one undo step; the caret ends after the `}}`.
    func accept(_ index: Int, in view: NSTextView) {
        guard let query, items.indices.contains(index) else { return }
        let insertion = VariableCompletion.insertion(of: items[index].name, for: query, in: view.string)
        close()
        // Its own undo step, not part of the typing before it.
        view.breakUndoCoalescing()
        view.insertText(insertion.text, replacementRange: insertion.range)
        view.setSelectedRange(NSRange(location: insertion.caret, length: 0))
    }

    func close() {
        query = nil
        items = []
        if panel.owner === self { panel.hide() }
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}

/// The one suggestion list window: a borderless panel that cannot become key, a child of the
/// window it hangs from, so the caret stays in the field. It takes clicks on its rows.
final class VariableSuggestionPanel {
    static let shared = VariableSuggestionPanel()

    static let rowHeight: CGFloat = 22
    static let maxRows = 8
    static let padding: CGFloat = 4
    static let widths: ClosedRange<CGFloat> = 200...320

    private var window: SuggestionWindow?
    private var list: SuggestionList?
    private(set) weak var owner: AnyObject?
    private var monitor: Any?
    var isShown: Bool { window?.isVisible ?? false }
    var frame: NSRect? { window?.frame }
    var canBecomeKey: Bool { window?.canBecomeKey ?? false }
    var selected: Int? { list?.selected }

    /// The trailing text of a row: the source, and "· Secret" for a secret. Never a value.
    static func detail(_ item: VariableSuggestion) -> String {
        item.isSecret ? "\(item.source) · Secret" : item.source
    }

    /// Below `rect` (screen coordinates), above it where the screen ends, hanging from `parent`.
    func show(_ items: [VariableSuggestion], selected: Int, theme: ThemeEnvironment, near rect: NSRect, in parent: NSWindow,
              owner: AnyObject, onPick: @escaping (Int) -> Void) {
        self.owner = owner
        let window = window ?? SuggestionWindow()
        self.window = window
        let list = list ?? SuggestionList()
        self.list = list
        list.theme = theme
        list.items = items
        list.selected = selected
        list.onPick = onPick

        let width = min(max(list.idealWidth + 2 * Self.padding, Self.widths.lowerBound), Self.widths.upperBound)
        let visible = CGFloat(min(items.count, Self.maxRows)) * Self.rowHeight
        let size = NSSize(width: width, height: visible + 2 * Self.padding)

        let box = NSView(frame: NSRect(origin: .zero, size: size))
        box.wantsLayer = true
        box.layer?.cornerRadius = 6
        box.layer?.borderWidth = 1
        box.layer?.borderColor = theme.color(.border).cgColor
        box.layer?.backgroundColor = theme.color(.backgroundElevated).cgColor
        let scroll = NSScrollView(frame: NSRect(x: 0, y: Self.padding, width: width, height: visible))
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = items.count > Self.maxRows
        scroll.scrollerStyle = .overlay
        list.frame = NSRect(x: 0, y: 0, width: width, height: CGFloat(items.count) * Self.rowHeight)
        scroll.documentView = list
        box.addSubview(scroll)
        window.contentView = box
        list.scrollToSelected()

        var origin = NSPoint(x: rect.minX - Self.padding, y: rect.minY - 4 - size.height)
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
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown, .scrollWheel, .keyDown]) { [weak self] event in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    let inside = event.window === self.window
                    let closes = switch event.type {
                    case .keyDown: event.modifierFlags.contains(.command)
                    default: !inside
                    }
                    if closes { (self.owner as? VariableSuggestions)?.close() ?? self.hide() }
                }
                return event
            }
        }
    }

    func select(_ index: Int) {
        list?.selected = index
        list?.scrollToSelected()
    }

    func hide() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        owner = nil
        guard let window else { return }
        window.parent?.removeChildWindow(window)
        window.orderOut(nil)
    }
}

/// The rows, drawn: the name in SF Mono 12 `text`, the source in 11 pt `textTertiary` at the
/// trailing end, the selected row on `selection`.
private final class SuggestionList: NSView {
    var theme: ThemeEnvironment?
    var items: [VariableSuggestion] = [] { didSet { needsDisplay = true } }
    var selected = 0 { didSet { needsDisplay = true } }
    var onPick: (Int) -> Void = { _ in }

    override var isFlipped: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    private static let nameFont = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
    private static let detailFont = NSFont.systemFont(ofSize: 11)
    private static let inset: CGFloat = 8

    var idealWidth: CGFloat {
        items.map { item in
            (item.name.rawValue as NSString).size(withAttributes: [.font: Self.nameFont]).width + 16
                + (VariableSuggestionPanel.detail(item) as NSString).size(withAttributes: [.font: Self.detailFont]).width
        }.max().map { ceil($0) + 2 * Self.inset } ?? 0
    }

    func rect(ofRow row: Int) -> NSRect {
        NSRect(x: 0, y: CGFloat(row) * VariableSuggestionPanel.rowHeight, width: bounds.width, height: VariableSuggestionPanel.rowHeight)
    }

    func scrollToSelected() {
        guard items.indices.contains(selected) else { return }
        scrollToVisible(rect(ofRow: selected))
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let theme else { return }
        for (row, item) in items.enumerated() {
            let box = rect(ofRow: row)
            guard box.intersects(dirtyRect) else { continue }
            if row == selected {
                theme.color(.selection).setFill()
                NSBezierPath(roundedRect: box.insetBy(dx: VariableSuggestionPanel.padding, dy: 0), xRadius: 4, yRadius: 4).fill()
            }
            let detail = NSAttributedString(string: VariableSuggestionPanel.detail(item), attributes: [.font: Self.detailFont, .foregroundColor: theme.color(.textTertiary)])
            let detailSize = detail.size()
            let detailX = box.maxX - Self.inset - detailSize.width
            detail.draw(at: NSPoint(x: detailX, y: box.midY - detailSize.height / 2))
            let style = NSMutableParagraphStyle()
            style.lineBreakMode = .byTruncatingTail
            let name = NSAttributedString(string: item.name.rawValue, attributes: [.font: Self.nameFont, .foregroundColor: theme.color(.text), .paragraphStyle: style])
            let nameHeight = name.size().height
            name.draw(in: NSRect(x: box.minX + Self.inset, y: box.midY - nameHeight / 2, width: max(0, detailX - 12 - box.minX - Self.inset), height: nameHeight))
        }
    }

    override func mouseDown(with event: NSEvent) {
        let row = Int(convert(event.locationInWindow, from: nil).y / VariableSuggestionPanel.rowHeight)
        if items.indices.contains(row) { onPick(row) }
    }
}

private final class SuggestionWindow: NSPanel {
    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        hidesOnDeactivate = true
        isReleasedWhenClosed = false
        becomesKeyOnlyIfNeeded = true
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

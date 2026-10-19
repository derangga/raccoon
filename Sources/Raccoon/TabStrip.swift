import AppKit
import RaccoonDomain

/// How wide each Tab is (design-system.md §6 Tab, boards 05 and 10). Tabs start at 196 pt and
/// shrink together; the selected one stops at 168 pt and the others at 104 pt, and past that
/// the strip scrolls with every Tab at its minimum.
nonisolated struct TabStripLayout: Equatable {
    static let ideal: CGFloat = 196
    static let minimum: CGFloat = 104
    static let selectedMinimum: CGFloat = 168

    let widths: [CGFloat]
    let scrolls: Bool

    init(count: Int, selected: Int?, available: CGFloat) {
        let share = available / CGFloat(max(count, 1))
        let isSelected = { (index: Int) in index == selected }
        if share >= Self.ideal {
            widths = Array(repeating: Self.ideal, count: count)
            scrolls = false
            return
        }
        let selectedWidth = selected == nil ? share : max(share, Self.selectedMinimum)
        let others = count - (selected == nil ? 0 : 1)
        let rest = others == 0 ? Self.minimum : (available - (selected == nil ? 0 : selectedWidth)) / CGFloat(others)
        scrolls = rest < Self.minimum || selectedWidth > available
        let width = scrolls ? Self.minimum : rest
        let chosen = scrolls ? Self.selectedMinimum : selectedWidth
        widths = (0..<count).map { isSelected($0) ? chosen : width }
    }
}

/// The row of Tabs over the editor, in the window's order, with + after the last one. It
/// scrolls once the Tabs reach their minimum widths, and keeps the selected Tab in view.
final class TabStripView: NSView {
    static let height: CGFloat = 34
    private static let newTabWidth: CGFloat = 34
    private static let fadeWidth: CGFloat = 24

    private let windowModel: WindowModel
    private let theme: ThemeEnvironment
    /// The ✕ on a Tab; whoever owns closing sets it.
    var onClose: ((TabModel) -> Void)?
    let scrollView = NSScrollView()
    private let document = FlippedView()
    let newTabButton: NSButton
    private(set) var items: [TabItemView] = []
    private(set) var scrolls = false
    private let bottomBorder = CALayer()
    private let fade = CAGradientLayer()
    /// The Tab last scrolled into view, so a resize does not scroll again.
    private var shownSelection: TabModel?

    init(window: WindowModel, theme: ThemeEnvironment) {
        self.windowModel = window
        self.theme = theme
        newTabButton = NSButton(image: NSImage(systemSymbolName: "plus", accessibilityDescription: "New Tab")!, target: nil, action: nil)
        super.init(frame: .zero)
        wantsLayer = true
        layer?.addSublayer(bottomBorder)
        scrollView.drawsBackground = false
        scrollView.hasHorizontalScroller = false
        scrollView.hasVerticalScroller = false
        scrollView.verticalScrollElasticity = .none
        scrollView.documentView = document
        scrollView.wantsLayer = true
        fade.startPoint = CGPoint(x: 0, y: 0.5)
        fade.endPoint = CGPoint(x: 1, y: 0.5)
        fade.colors = [NSColor.clear, .black, .black, .clear].map(\.cgColor)
        addSubview(scrollView)
        newTabButton.isBordered = false
        newTabButton.toolTip = "New Tab"
        newTabButton.target = self
        newTabButton.action = #selector(newTab)
        addSubview(newTabButton)
        setAccessibilityElement(true)
        setAccessibilityRole(.tabGroup)
        setAccessibilityLabel("Tabs")
        theme.paint(self) { strip, theme in
            strip.layer?.backgroundColor = theme.color(.backgroundRecessed).cgColor
            strip.bottomBorder.backgroundColor = theme.color(.border).cgColor
            strip.newTabButton.contentTintColor = theme.color(.textSecondary)
        }
        render()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func accessibilityChildren() -> [Any]? { items }

    /// Follows the window's Tabs and selection. Only the order and the selection are observed
    /// here; each item follows its own Tab.
    private func render() {
        let (tabs, selected) = withObservationTracking { (windowModel.tabs, windowModel.selected) } onChange: { [weak self] in
            Task { @MainActor in self?.render() }
        }
        let old = items
        items = tabs.map { model in old.first { $0.model === model } ?? item(for: model) }
        for item in old where !items.contains(where: { $0 === item }) { item.removeFromSuperview() }
        for item in items {
            if item.superview == nil { document.addSubview(item) }
            item.isSelected = item.model.tab.id == selected
        }
        needsLayout = true
    }

    private func item(for model: TabModel) -> TabItemView {
        TabItemView(model: model, theme: theme, title: { [weak self] in self?.windowModel.name(of: model.tab) ?? model.tab.title }, onSelect: { [weak self] in self?.windowModel.select(model.tab.id) },
                    onClose: { [weak self] in self?.onClose?(model) })
    }

    @objc private func newTab() { windowModel.newTab() }

    override func layout() {
        super.layout()
        let height = bounds.height
        let available = bounds.width - Self.newTabWidth
        let layout = TabStripLayout(count: items.count, selected: items.firstIndex(where: \.isSelected), available: available)
        scrolls = layout.scrolls
        var x: CGFloat = 0
        // The selected Tab covers the strip's bottom border and joins the editor.
        for (item, width) in zip(items, layout.widths) {
            item.frame = NSRect(x: x, y: 0, width: width, height: item.isSelected ? height : height - 1)
            x += width
        }
        let shown = min(x, available)
        bottomBorder.frame = NSRect(x: 0, y: 0, width: bounds.width, height: 1)
        scrollView.frame = NSRect(x: 0, y: 0, width: shown, height: height)
        document.frame = NSRect(x: 0, y: 0, width: x, height: height)
        newTabButton.frame = NSRect(x: shown, y: 1, width: Self.newTabWidth, height: height - 1)
        if scrolls, shown > 0 {
            fade.frame = scrollView.bounds
            let edge = Self.fadeWidth / shown
            fade.locations = [0, edge, 1 - edge, 1].map { NSNumber(value: Double($0)) }
            scrollView.layer?.mask = fade
        } else {
            scrollView.layer?.mask = nil
        }
        if let selected = items.first(where: \.isSelected), selected.model !== shownSelection {
            shownSelection = selected.model
            selected.scrollToVisible(selected.bounds)
        }
    }
}

/// One Tab: `[state glyph or Draft dot] [method badge] name [slot]` (design-system.md §6 Tab).
final class TabItemView: NSView {
    let model: TabModel
    private let theme: ThemeEnvironment
    private let onSelect: () -> Void
    private let onClose: () -> Void

    let glyph = NSImageView()
    /// The Draft cue that reads in every script, italic or not (Open UI Q4).
    let draftDot = NSView()
    let badge = NSTextField(labelWithString: "")
    let spinner = NSProgressIndicator()
    let name = NSTextField(labelWithString: "")
    let dot = NSView()
    let closeButton: NSButton
    private let topRule = CALayer()
    private let rightBorder = CALayer()
    private var ticking: Task<Void, Never>?

    private static let nameFont = NSFont.systemFont(ofSize: 13)
    private static let draftFont = NSFontManager.shared.convert(nameFont, toHaveTrait: .italicFontMask)

    var isSelected = false { didSet { if isSelected != oldValue { draw() } } }
    var isHovered = false { didSet { if isHovered != oldValue { draw() } } }

    /// The window's name for the Tab: a Request's comes from the index.
    private let title: () -> String

    init(model: TabModel, theme: ThemeEnvironment, title: @escaping () -> String, onSelect: @escaping () -> Void, onClose: @escaping () -> Void) {
        self.model = model
        self.title = title
        self.theme = theme
        self.onSelect = onSelect
        self.onClose = onClose
        let xmark = NSImage(systemSymbolName: "xmark", accessibilityDescription: "Close Tab")!
        closeButton = NSButton(image: xmark.withSymbolConfiguration(.init(pointSize: 8, weight: .bold)) ?? xmark, target: nil, action: nil)
        super.init(frame: .zero)
        wantsLayer = true
        layer?.addSublayer(rightBorder)
        layer?.addSublayer(topRule)
        glyph.image = NSImage(systemSymbolName: "exclamationmark.triangle", accessibilityDescription: "Changed on Disk")
        glyph.symbolConfiguration = .init(pointSize: 10, weight: .medium)
        badge.font = .monospacedSystemFont(ofSize: 10, weight: .bold)
        badge.lineBreakMode = .byTruncatingTail
        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.isDisplayedWhenStopped = false
        name.lineBreakMode = .byTruncatingTail
        name.usesSingleLineMode = true
        dot.wantsLayer = true
        dot.layer?.cornerRadius = 4
        draftDot.wantsLayer = true
        draftDot.layer?.cornerRadius = 3
        closeButton.isBordered = false
        closeButton.wantsLayer = true
        closeButton.layer?.cornerRadius = 4
        closeButton.toolTip = "Close Tab"
        closeButton.target = self
        closeButton.action = #selector(close)
        for part in [glyph, draftDot, spinner, badge, name, dot, closeButton] as [NSView] {
            part.setAccessibilityElement(false)
            addSubview(part)
        }
        setAccessibilityElement(true)
        setAccessibilityRole(.radioButton)
        setAccessibilitySubrole(.tabButtonSubrole)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect], owner: self))
        render()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// "Edited", "Draft", "Sending", "Changed on Disk", the ones that apply, in that order.
    static func accessibilityValue(_ tab: Tab) -> String {
        let sending = if case .sending = tab.response { true } else { false }
        return [(tab.isDirty, "Edited"), (tab.source == .draft, "Draft"), (sending, "Sending"), (tab.isChangedOnDisk, "Changed on Disk")]
            .filter(\.0).map(\.1).joined(separator: ", ")
    }

    /// Redraws from the Tab and the Flavor, and again whenever either changes.
    private func render() {
        withObservationTracking { draw() } onChange: { [weak self] in
            Task { @MainActor in self?.render() }
        }
    }

    private func draw() {
        let tab = model.tab
        ticking?.cancel()
        var spins = false
        if case .sending(let since) = tab.response {
            spins = model.showsSpinner
            // Nothing for 150 ms, so a fast local API never flashes a spinner.
            if !spins {
                let wait = since + .milliseconds(150) - model.now
                ticking = Task { [weak self] in
                    try? await Task.sleep(for: wait)
                    if !Task.isCancelled { self?.draw() }
                }
            }
        }
        if spins, spinner.isHidden {
            spinner.alphaValue = 0
            NSAnimationContext.runAnimationGroup { $0.duration = 0.12; spinner.animator().alphaValue = 1 }
        }
        spinner.isHidden = !spins
        if spins { spinner.startAnimation(nil) } else { spinner.stopAnimation(nil) }
        glyph.isHidden = !tab.isChangedOnDisk
        draftDot.isHidden = tab.source != .draft
        badge.isHidden = spins
        badge.stringValue = tab.definition.method
        let title = self.title()
        name.stringValue = title
        name.font = tab.source == .draft ? Self.draftFont : Self.nameFont
        toolTip = title
        // The macOS document convention: hovering a Dirty Tab swaps its dot for ✕.
        dot.isHidden = !(tab.isDirty || tab.isChangedOnDisk) || isHovered
        closeButton.isHidden = !isHovered

        layer?.backgroundColor = theme.color(isSelected ? .background : isHovered ? .rowHover : .backgroundRecessed).cgColor
        topRule.backgroundColor = theme.color(.accent).cgColor
        topRule.isHidden = !isSelected
        rightBorder.backgroundColor = theme.color(.border).cgColor
        glyph.contentTintColor = theme.color(.warning)
        badge.textColor = theme.color(.method(tab.definition.method))
        name.textColor = theme.color(isSelected ? .text : .textSecondary)
        dot.layer?.backgroundColor = theme.color(.dirtyDot).cgColor
        draftDot.layer?.backgroundColor = theme.color(.accent).cgColor
        closeButton.contentTintColor = theme.color(.textSecondary)
        closeButton.layer?.backgroundColor = theme.color(.selection).cgColor

        setAccessibilityTitle("\(tab.definition.method) \(title)")
        setAccessibilityValue(Self.accessibilityValue(tab))
        setAccessibilitySelected(isSelected)
        needsLayout = true
    }

    override func layout() {
        super.layout()
        let height = bounds.height
        rightBorder.frame = NSRect(x: bounds.width - 1, y: 0, width: 1, height: height)
        topRule.frame = NSRect(x: 0, y: height - 2, width: bounds.width, height: 2)
        // Centred on the strip's 33 pt above its border, so selecting a Tab moves nothing.
        let middle = height - (TabStripView.height - 1) / 2
        var x: CGFloat = 10
        func place(_ view: NSView, width: CGFloat, height: CGFloat) {
            view.frame = NSRect(x: x, y: (middle - height / 2).rounded(), width: width, height: height)
            x += width + 6
        }
        if !glyph.isHidden { place(glyph, width: 12, height: 12) }
        if !draftDot.isHidden { place(draftDot, width: 6, height: 6) }
        if !spinner.isHidden { place(spinner, width: 12, height: 12) }
        if !badge.isHidden {
            // The cell's size: a truncating label's intrinsic width leaves out its padding.
            let size = badge.cell?.cellSize ?? badge.intrinsicContentSize
            place(badge, width: min(size.width.rounded(.up), 64), height: size.height)
        }
        let slot = bounds.width - 1 - 6 - 16
        let nameHeight = name.intrinsicContentSize.height
        name.frame = NSRect(x: x, y: (middle - nameHeight / 2).rounded(), width: max(0, slot - 6 - x), height: nameHeight)
        let slotY = (middle - 8).rounded()
        closeButton.frame = NSRect(x: slot, y: slotY, width: 16, height: 16)
        dot.frame = NSRect(x: slot + 4, y: slotY + 4, width: 8, height: 8)
    }

    override func mouseDown(with event: NSEvent) { onSelect() }
    override func mouseEntered(with event: NSEvent) { isHovered = true }
    override func mouseExited(with event: NSEvent) { isHovered = false }

    override func accessibilityPerformPress() -> Bool {
        onSelect()
        return true
    }

    @objc private func close() { onClose() }
}

/// The content pane: the tab strip over the one TabViewController.
final class ContentViewController: NSViewController {
    let strip: TabStripView
    let tab: TabViewController

    init(strip: TabStripView, tab: TabViewController) {
        self.strip = strip
        self.tab = tab
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func loadView() {
        let root = NSView()
        addChild(tab)
        for part in [strip, tab.view] {
            part.translatesAutoresizingMaskIntoConstraints = false
            root.addSubview(part)
        }
        NSLayoutConstraint.activate([
            strip.topAnchor.constraint(equalTo: root.topAnchor),
            strip.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            strip.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            strip.heightAnchor.constraint(equalToConstant: TabStripView.height),
            tab.view.topAnchor.constraint(equalTo: strip.bottomAnchor),
            tab.view.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            tab.view.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            tab.view.bottomAnchor.constraint(equalTo: root.bottomAnchor),
        ])
        view = root
    }
}

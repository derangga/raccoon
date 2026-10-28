import AppKit
import os
import RaccoonDomain

/// The content area while no Tab is open (design-system §6 Empty state): the raccoon mark and
/// one row per command, each running its menu item's action through the responder chain.
final class EmptyStateView: NSView {
    private static let log = Logger(subsystem: "Raccoon", category: "EmptyState")
    /// The menu items the rows mirror, in order. Their titles and shortcuts are read from the menu.
    static let actions = [#selector(AppDelegate.newTab(_:)), #selector(AppDelegate.importFromPostman(_:)), #selector(AppDelegate.editEnvironments(_:))]

    let mark = NSImageView()
    private(set) var rows: [CommandRow] = []

    init(theme: ThemeEnvironment, menu: NSMenu?) {
        super.init(frame: .zero)
        wantsLayer = true
        if let image = Bundle.module.image(forResource: "RaccoonFace") {
            image.isTemplate = true
            image.size = NSSize(width: 160, height: 160)
            mark.image = image
        } else {
            Self.log.error("RaccoonFace@2x.png is missing from the bundle; the empty state shows no mark")
        }
        mark.imageScaling = .scaleProportionallyUpOrDown
        mark.setAccessibilityElement(false)
        rows = Self.actions.compactMap { action in menu.flatMap { Self.item(for: action, in: $0) }.map { CommandRow(item: $0, theme: theme) } }

        let column = NSStackView(views: [mark] + rows)
        column.orientation = .vertical
        column.alignment = .centerX
        column.spacing = 0
        column.setCustomSpacing(24, after: mark)
        column.translatesAutoresizingMaskIntoConstraints = false
        addSubview(column)
        NSLayoutConstraint.activate([
            mark.widthAnchor.constraint(equalToConstant: 160),
            mark.heightAnchor.constraint(equalToConstant: 160),
            column.centerXAnchor.constraint(equalTo: centerXAnchor),
            column.centerYAnchor.constraint(equalTo: centerYAnchor, constant: -12),
        ] + rows.flatMap { [$0.widthAnchor.constraint(equalToConstant: 280), $0.heightAnchor.constraint(equalToConstant: 32)] })
        theme.paint(self) { view, theme in
            view.layer?.backgroundColor = theme.color(.background).cgColor
            view.mark.contentTintColor = theme.color(.textTertiary).withAlphaComponent(0.4)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    private static func item(for action: Selector, in menu: NSMenu) -> NSMenuItem? {
        for item in menu.items {
            if item.action == action { return item }
            if let found = item.submenu.flatMap({ Self.item(for: action, in: $0) }) { return found }
        }
        return nil
    }
}

/// One command: its menu title on the leading edge, its shortcut as keycaps on the trailing edge.
final class CommandRow: NSView {
    let action: Selector
    let title: NSTextField
    let keys: [String]
    private let theme: ThemeEnvironment
    private let keycaps = NSStackView()
    private var isHovered = false { didSet { paint() } }

    init(item: NSMenuItem, theme: ThemeEnvironment) {
        action = item.action!
        title = NSTextField(labelWithString: item.title)
        keys = Self.keys(item)
        self.theme = theme
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 6
        title.font = .systemFont(ofSize: 15)
        keycaps.spacing = 4
        for key in keys { keycaps.addArrangedSubview(Keycap(key)) }
        for view in [title, keycaps] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        NSLayoutConstraint.activate([
            title.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            title.centerYAnchor.constraint(equalTo: centerYAnchor),
            keycaps.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            keycaps.centerYAnchor.constraint(equalTo: centerYAnchor),
            title.trailingAnchor.constraint(lessThanOrEqualTo: keycaps.leadingAnchor, constant: -8),
        ])
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self))
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel(item.title)
        theme.paint(self) { row, _ in row.paint() }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// The shortcut as the menu bar shows it: ⌃ ⌥ ⇧ ⌘, then the key.
    static func keys(_ item: NSMenuItem) -> [String] {
        guard !item.keyEquivalent.isEmpty else { return [] }
        let mask = item.keyEquivalentModifierMask
        let modifiers: [(NSEvent.ModifierFlags, String)] = [(.control, "⌃"), (.option, "⌥"), (.shift, "⇧"), (.command, "⌘")]
        return modifiers.filter { mask.contains($0.0) }.map(\.1) + [item.keyEquivalent.uppercased()]
    }

    private func paint() {
        layer?.backgroundColor = isHovered ? theme.color(.rowHover).cgColor : NSColor.clear.cgColor
        title.textColor = theme.color(.textSecondary)
        for case let cap as Keycap in keycaps.arrangedSubviews { cap.paint(theme) }
    }

    override func mouseEntered(with event: NSEvent) { isHovered = true }
    override func mouseExited(with event: NSEvent) { isHovered = false }
    override func mouseDown(with event: NSEvent) {}
    override func mouseUp(with event: NSEvent) {
        guard bounds.contains(convert(event.locationInWindow, from: nil)) else { return }
        run()
    }

    override func accessibilityPerformPress() -> Bool { run() }

    /// The menu item's own action, so the row does exactly what the menu does.
    @discardableResult private func run() -> Bool { NSApp.sendAction(action, to: nil, from: self) }
}

/// One key of a shortcut: a 20 pt chip on `backgroundElevated` with a `border` edge.
private final class Keycap: NSView {
    private let label: NSTextField

    init(_ key: String) {
        label = NSTextField(labelWithString: key)
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 4
        layer?.borderWidth = 1
        label.font = .systemFont(ofSize: 12)
        label.alignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 20),
            widthAnchor.constraint(greaterThanOrEqualToConstant: 20),
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func paint(_ theme: ThemeEnvironment) {
        layer?.backgroundColor = theme.color(.backgroundElevated).cgColor
        layer?.borderColor = theme.color(.border).cgColor
        label.textColor = theme.color(.textSecondary)
    }
}

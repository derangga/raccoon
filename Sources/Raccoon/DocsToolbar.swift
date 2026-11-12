import AppKit
import RaccoonDomain

/// The format commands of the Docs editor, in the Format menu's order and groups. Menu items,
/// toolbar buttons and the pull-down all carry `rawValue` as their tag and send
/// `DocsTextView.applyFormat(_:)`, so the Format menu is enabled only while that editor is first
/// responder.
enum DocsFormat: Int, CaseIterable {
    case normal, heading1, heading2, heading3, bold, italic, strikethrough, bulleted, numbered, link, quote, code, codeBlock

    static let groups: [[DocsFormat]] = [
        [.normal, .heading1, .heading2, .heading3],
        [.bold, .italic, .strikethrough],
        [.bulleted, .numbered],
        [.link, .quote, .code, .codeBlock],
    ]

    var name: String {
        switch self {
        case .normal: "Normal text"
        case .heading1: "Heading 1"
        case .heading2: "Heading 2"
        case .heading3: "Heading 3"
        case .bold: "Bold"
        case .italic: "Italic"
        case .strikethrough: "Strikethrough"
        case .bulleted: "Bulleted list"
        case .numbered: "Numbered list"
        case .link: "Link"
        case .quote: "Quote"
        case .code: "Inline code"
        case .codeBlock: "Code block"
        }
    }

    /// nil for Link, which asks for the URL first.
    var command: DocsEdit.Command? {
        switch self {
        case .normal: .block(.paragraph)
        case .heading1: .block(.heading(1))
        case .heading2: .block(.heading(2))
        case .heading3: .block(.heading(3))
        case .bold: .toggle(.bold)
        case .italic: .toggle(.italic)
        case .strikethrough: .toggle(.strikethrough)
        case .bulleted: .block(.bullet)
        case .numbered: .block(.numbered)
        case .link: nil
        case .quote: .block(.quote)
        case .code: .toggle(.code)
        case .codeBlock: .block(.codeBlock)
        }
    }

    var key: (character: String, modifiers: NSEvent.ModifierFlags) {
        switch self {
        case .normal: ("0", [.option, .command])
        case .heading1: ("1", [.option, .command])
        case .heading2: ("2", [.option, .command])
        case .heading3: ("3", [.option, .command])
        case .bold: ("b", .command)
        case .italic: ("i", .command)
        case .strikethrough: ("x", [.shift, .command])
        case .bulleted: ("8", [.shift, .command])
        case .numbered: ("7", [.shift, .command])
        case .link: ("k", .command)
        case .quote: ("9", [.shift, .command])
        case .code: ("e", .command)
        case .codeBlock: ("c", [.option, .command])
        }
    }

    var symbol: String? {
        switch self {
        case .bold: "bold"
        case .italic: "italic"
        case .strikethrough: "strikethrough"
        case .bulleted: "list.bullet"
        case .numbered: "list.number"
        case .link: "link"
        case .quote: "text.quote"
        case .code: "chevron.left.forwardslash.chevron.right"
        case .codeBlock: "curlybraces"
        case .normal, .heading1, .heading2, .heading3: nil
        }
    }

    /// "⌥⌘1": the glyphs in the system's order.
    var shortcut: String {
        let (character, modifiers) = key
        return (modifiers.contains(.option) ? "⌥" : "") + (modifiers.contains(.shift) ? "⇧" : "") + "⌘" + character.uppercased()
    }

    /// "Bold (⌘B)": the tooltip and accessibility label.
    var label: String { "\(name) (\(shortcut))" }

    /// Sends `applyFormat` up the responder chain, or to `target`.
    func menuItem(target: AnyObject? = nil) -> NSMenuItem {
        let item = NSMenuItem(title: self == .link ? "Link…" : name, action: #selector(DocsTextView.applyFormat(_:)), keyEquivalent: key.character)
        item.keyEquivalentModifierMask = key.modifiers
        item.tag = rawValue
        item.target = target
        return item
    }

    /// Whether the caret's state already has this style.
    func isOn(in state: DocsEdit.State) -> Bool {
        switch self {
        case .bold: state.inline.contains(.bold)
        case .italic: state.inline.contains(.italic)
        case .strikethrough: state.inline.contains(.strikethrough)
        case .code: state.inline.contains(.code)
        case .bulleted: state.block == .bullet
        case .numbered: state.block == .numbered
        case .quote: state.block == .quote
        case .codeBlock: state.block == .codeBlock
        case .link: state.link != nil
        case .normal, .heading1, .heading2, .heading3: false
        }
    }
}

/// The Docs toolbar (design-system.md §6): floats over the pane's top-leading corner while the
/// editor is first responder. Its buttons never take focus, so a click leaves the editor focused.
final class DocsToolbar: NSView {
    private let theme: ThemeEnvironment
    private let styleButton: ToolbarButton
    private(set) var buttons: [DocsFormat: ToolbarButton] = [:]
    private var separators: [NSView] = []
    private let styleMenu = NSMenu()

    init(theme: ThemeEnvironment, editor: DocsTextView) {
        self.theme = theme
        styleButton = ToolbarButton(label: "Text style", title: "Normal text", width: 120, theme: theme)
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 8
        layer?.masksToBounds = false
        // The Dropdown list's shadow, as the Find panel draws it.
        layer?.shadowOpacity = 0.12
        layer?.shadowRadius = 6
        layer?.shadowOffset = CGSize(width: 0, height: -4)
        layer?.shadowColor = NSColor.black.cgColor
        layer?.borderWidth = 1
        setAccessibilityRole(.toolbar)
        setAccessibilityLabel("Docs toolbar")

        DocsFormat.groups[0].forEach { styleMenu.addItem($0.menuItem(target: editor)) }
        styleButton.target = self
        styleButton.action = #selector(openStyleMenu)

        func group(_ formats: [DocsFormat]) -> [NSView] {
            formats.map { format in
                let button = ToolbarButton(label: format.label, symbol: format.symbol, theme: theme)
                button.tag = format.rawValue
                button.target = editor
                button.action = #selector(DocsTextView.applyFormat(_:))
                buttons[format] = button
                return button
            }
        }
        let groups = [[styleButton as NSView]] + DocsFormat.groups.dropFirst().map(group)
        var items: [NSView] = []
        for (index, views) in groups.enumerated() {
            if index > 0 {
                let separator = NSView()
                separator.wantsLayer = true
                separator.translatesAutoresizingMaskIntoConstraints = false
                separator.widthAnchor.constraint(equalToConstant: 1).isActive = true
                separator.heightAnchor.constraint(equalToConstant: 16).isActive = true
                separators.append(separator)
                items.append(separator)
            }
            items += views
        }
        let row = NSStackView(views: items)
        row.spacing = 4
        row.edgeInsets = NSEdgeInsets(top: 0, left: 4, bottom: 0, right: 4)
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)
        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 32),
            row.topAnchor.constraint(equalTo: topAnchor),
            row.bottomAnchor.constraint(equalTo: bottomAnchor),
            row.leadingAnchor.constraint(equalTo: leadingAnchor),
            row.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])
        theme.paint(self) { bar, theme in
            bar.layer?.backgroundColor = theme.color(.backgroundElevated).cgColor
            bar.layer?.borderColor = theme.color(.border).cgColor
            bar.separators.forEach { $0.layer?.backgroundColor = theme.color(.border).cgColor }
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// The buttons show the caret's state; the pull-down, the caret line's block.
    func update(_ state: DocsEdit.State) {
        for (format, button) in buttons { button.isOn = format.isOn(in: state) }
        styleButton.setTitle(Self.title(of: state.block))
    }

    var styleTitle: String { styleButton.title }

    static func title(of block: DocsEdit.Block) -> String {
        switch block {
        case .paragraph: DocsFormat.normal.name
        case .heading(let level): level <= 3 ? DocsFormat.allCases[level].name : "Heading \(level)"
        case .bullet: DocsFormat.bulleted.name
        case .numbered: DocsFormat.numbered.name
        case .quote: DocsFormat.quote.name
        case .codeBlock: DocsFormat.codeBlock.name
        }
    }

    @objc private func openStyleMenu() {
        styleMenu.popUp(positioning: nil, at: NSPoint(x: 0, y: -2), in: styleButton)
    }
}

/// A borderless 28 × 24 icon button, or a titled one with a chevron: `rowHover` under the
/// pointer, the glyph in `accent` while `isOn`.
final class ToolbarButton: NSButton {
    private let theme: ThemeEnvironment
    private var hovered = false
    private let titled: Bool
    var isOn = false { didSet { redraw() } }

    init(label: String, symbol: String? = nil, title: String? = nil, width: CGFloat = 28, theme: ThemeEnvironment) {
        self.theme = theme
        titled = title != nil
        super.init(frame: .zero)
        isBordered = false
        refusesFirstResponder = true
        wantsLayer = true
        layer?.cornerRadius = 4
        toolTip = label
        setAccessibilityLabel(label)
        let name = title == nil ? symbol : "chevron.down"
        if let name {
            image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?.withSymbolConfiguration(.init(pointSize: titled ? 9 : 13, weight: .regular))
        }
        if let title {
            self.title = title
            imagePosition = .imageTrailing
            alignment = .left
        } else {
            imagePosition = .imageOnly
        }
        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([widthAnchor.constraint(equalToConstant: width), heightAnchor.constraint(equalToConstant: 24)])
        theme.paint(self) { button, _ in button.redraw() }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var acceptsFirstResponder: Bool { false }

    func setTitle(_ text: String) {
        title = text
        redraw()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self))
    }

    override func mouseEntered(with event: NSEvent) {
        hovered = true
        redraw()
    }

    override func mouseExited(with event: NSEvent) {
        hovered = false
        redraw()
    }

    private func redraw() {
        layer?.backgroundColor = (hovered ? theme.color(.rowHover) : .clear).cgColor
        contentTintColor = theme.color(isOn ? .accent : .textSecondary)
        if titled {
            attributedTitle = NSAttributedString(string: title, attributes: [.font: NSFont.systemFont(ofSize: 13), .foregroundColor: theme.color(.text)])
        }
    }
}

/// The Link popover's content: a URL field. Return applies, Esc cancels.
final class LinkPopoverController: NSViewController, NSTextFieldDelegate {
    let field = NSTextField()
    var onApply: (String) -> Void = { _ in }
    var onCancel: () -> Void = {}

    init(url: String) {
        super.init(nibName: nil, bundle: nil)
        field.stringValue = url
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 280, height: 44))
        field.frame = NSRect(x: 12, y: 10, width: 256, height: 24)
        field.placeholderString = "https://"
        field.delegate = self
        field.setAccessibilityLabel("Link URL")
        view.addSubview(field)
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        switch selector {
        case #selector(NSResponder.insertNewline(_:)): onApply(field.stringValue)
        case #selector(NSResponder.cancelOperation(_:)): onCancel()
        default: return false
        }
        return true
    }
}

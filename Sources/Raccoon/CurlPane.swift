import AppKit
import RaccoonDomain

/// The Curl pane (design-system §6 Inspector, board 11): Copy as Curl of the selected Tab, live,
/// with secrets as `{{name}}`. The command wraps anywhere and scrolls, never truncated, because
/// Copy gives exactly what is shown. Include secrets changes only what Copy puts on the pasteboard.
final class CurlPaneView: NSView {
    /// Copies the selected Tab's command; true fills in the secrets.
    var onCopy: ((Bool) -> Void)?

    private let theme: ThemeEnvironment
    /// The 6 pt-radius `border` box on `background` the command sits in.
    let box = NSView()
    let textView: NSTextView
    private let scroll = NSScrollView()
    private let noteLabel = NSTextField(wrappingLabelWithString: "")
    private let voidStack = NSStackView()
    private let glyph = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let textLabel = NSTextField(wrappingLabelWithString: "")
    /// Off at every launch; never written anywhere.
    let includeSecrets = NSButton(checkboxWithTitle: "Include secrets", target: nil, action: nil)
    let copyButton = NSButton(title: "Copy", target: nil, action: nil)
    private(set) var note: String?
    /// "No curl command yet" when Variables are missing or the URL is invalid.
    private(set) var voidTitle: String?
    /// Why there is no command.
    private(set) var voidText: String?

    init(theme: ThemeEnvironment) {
        self.theme = theme
        // TextKit 1, so the wrap is the layout manager's and a 20 KB body lays out at once.
        textView = NSTextView(usingTextLayoutManager: false)
        super.init(frame: NSRect(x: 0, y: 0, width: 280, height: 400))
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        // With the 5 pt line padding: 10 pt in from the box's sides, 8 pt from its top.
        textView.textContainerInset = NSSize(width: 4, height: 7)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: .greatestFiniteMagnitude)
        scroll.documentView = textView
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false
        box.wantsLayer = true
        box.layer?.cornerRadius = 6
        box.layer?.borderWidth = 1
        box.addSubview(scroll)

        noteLabel.font = .systemFont(ofSize: 11)
        glyph.image = NSImage(systemSymbolName: "exclamationmark.circle", accessibilityDescription: nil)
        glyph.symbolConfiguration = .init(pointSize: 18, weight: .regular)
        titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        textLabel.font = .systemFont(ofSize: 12)
        textLabel.alignment = .center
        voidStack.orientation = .vertical
        voidStack.alignment = .centerX
        voidStack.spacing = 8
        for view in [glyph, titleLabel, textLabel] { voidStack.addArrangedSubview(view) }

        includeSecrets.font = .systemFont(ofSize: 12)
        copyButton.isBordered = false
        copyButton.wantsLayer = true
        copyButton.layer?.cornerRadius = 6
        copyButton.layer?.borderWidth = 1
        copyButton.target = self
        copyButton.action = #selector(copy(_:))

        let rule = ThemedView(theme: theme, fill: .border)
        let footer = NSView()
        footer.addSubview(includeSecrets)
        footer.addSubview(copyButton)
        for view in [box, scroll, noteLabel, voidStack, rule, footer, includeSecrets, copyButton] {
            view.translatesAutoresizingMaskIntoConstraints = false
        }
        for view in [box, noteLabel, voidStack, rule, footer] { addSubview(view) }
        NSLayoutConstraint.activate([
            box.topAnchor.constraint(equalTo: topAnchor, constant: 10),
            box.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            box.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            box.bottomAnchor.constraint(equalTo: noteLabel.topAnchor, constant: -12),
            scroll.topAnchor.constraint(equalTo: box.topAnchor, constant: 1),
            scroll.leadingAnchor.constraint(equalTo: box.leadingAnchor, constant: 1),
            scroll.trailingAnchor.constraint(equalTo: box.trailingAnchor, constant: -1),
            scroll.bottomAnchor.constraint(equalTo: box.bottomAnchor, constant: -1),
            noteLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            noteLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            noteLabel.bottomAnchor.constraint(equalTo: rule.topAnchor, constant: -10),
            voidStack.centerXAnchor.constraint(equalTo: centerXAnchor),
            voidStack.centerYAnchor.constraint(equalTo: centerYAnchor, constant: -20),
            voidStack.widthAnchor.constraint(lessThanOrEqualTo: widthAnchor, constant: -40),
            textLabel.widthAnchor.constraint(lessThanOrEqualTo: widthAnchor, constant: -40),
            rule.leadingAnchor.constraint(equalTo: leadingAnchor),
            rule.trailingAnchor.constraint(equalTo: trailingAnchor),
            rule.heightAnchor.constraint(equalToConstant: 1),
            rule.bottomAnchor.constraint(equalTo: footer.topAnchor),
            footer.leadingAnchor.constraint(equalTo: leadingAnchor),
            footer.trailingAnchor.constraint(equalTo: trailingAnchor),
            footer.bottomAnchor.constraint(equalTo: bottomAnchor),
            footer.heightAnchor.constraint(equalToConstant: 40),
            includeSecrets.leadingAnchor.constraint(equalTo: footer.leadingAnchor, constant: 12),
            includeSecrets.centerYAnchor.constraint(equalTo: footer.centerYAnchor),
            copyButton.trailingAnchor.constraint(equalTo: footer.trailingAnchor, constant: -12),
            copyButton.centerYAnchor.constraint(equalTo: footer.centerYAnchor),
            copyButton.heightAnchor.constraint(equalToConstant: 24),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    @objc private func copy(_ sender: Any?) { onCopy?(includeSecrets.state == .on) }

    /// `kinds` finds the secrets left as `{{name}}`; `environment` is the Active Environment's name.
    /// A nil preview is no Tab open.
    func render(_ preview: CurlPreview?, kinds: VariableKinds?, environment: String?) {
        let command: String? = if case .command(let text) = preview { text } else { nil }
        switch preview {
        case nil:
            (voidTitle, voidText) = (nil, "Open a Tab to see its curl command.")
        case .command:
            (voidTitle, voidText) = (nil, nil)
        case .noURL:
            (voidTitle, voidText) = (nil, "Type a URL to see the curl command.")
        case .undefined(let names):
            (voidTitle, voidText) = ("No curl command yet", VariableName.notDefined(names, in: environment))
        case .invalidURL(let url):
            (voidTitle, voidText) = ("No curl command yet", "After substitution the URL was \(url).")
        }
        note = command.map { _ in "Resolved with \(environment ?? "Globals"). Disabled Rows are left out." }

        box.isHidden = command == nil
        noteLabel.isHidden = command == nil
        voidStack.isHidden = command != nil
        glyph.isHidden = voidTitle == nil
        titleLabel.isHidden = voidTitle == nil
        includeSecrets.isHidden = command == nil
        copyButton.isEnabled = command != nil

        box.layer?.backgroundColor = theme.color(.background).cgColor
        box.layer?.borderColor = theme.color(.border).cgColor
        noteLabel.stringValue = note ?? ""
        noteLabel.textColor = theme.color(.textTertiary)
        glyph.contentTintColor = theme.color(.statusFailed)
        titleLabel.stringValue = voidTitle ?? ""
        titleLabel.textColor = theme.color(.statusFailed)
        textLabel.stringValue = voidText ?? ""
        textLabel.textColor = theme.color(.textTertiary)
        includeSecrets.bezelColor = theme.color(.accent)
        includeSecrets.attributedTitle = NSAttributedString(string: "Include secrets", attributes: [
            .font: NSFont.systemFont(ofSize: 12), .foregroundColor: theme.color(.text),
        ])
        renderCopy()
        if let command, let kinds { show(command, kinds: kinds) }
    }

    /// Primary while there is a command; disabled, a plain button with `textDisabled` ink.
    private func renderCopy() {
        let enabled = copyButton.isEnabled
        let (fill, edge, ink) = enabled
            ? (ColorToken.accent, ColorToken.accent, ColorToken.textOnAccent)
            : (.background, .border, .textDisabled)
        copyButton.attributedTitle = NSAttributedString(string: "Copy", attributes: [
            .font: NSFont.systemFont(ofSize: 12, weight: enabled ? .semibold : .regular), .foregroundColor: theme.color(ink),
        ])
        copyButton.layer?.backgroundColor = theme.color(fill).cgColor
        copyButton.layer?.borderColor = theme.color(edge).cgColor
        copyButton.removeConstraints(copyButton.constraints.filter { $0.firstAttribute == .width })
        copyButton.widthAnchor.constraint(equalToConstant: (copyButton.attributedTitle.size().width + 24).rounded(.up)).isActive = true
    }

    /// SF Mono 11 / 17, wrapped at any character, colored by `Highlighter.curl`. A secret's
    /// `{{name}}` is drawn last, in `variableSecret` with its dotted underline. Attributes only:
    /// the text stays what Copy puts on the pasteboard.
    private func show(_ command: String, kinds: VariableKinds) {
        let font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byCharWrapping
        paragraph.minimumLineHeight = 17
        paragraph.maximumLineHeight = 17
        let text = NSMutableAttributedString(string: command, attributes: [
            .font: font, .foregroundColor: theme.color(.text), .paragraphStyle: paragraph,
        ])
        for range in Highlighter.curl(command) {
            text.addAttribute(.foregroundColor, value: theme.color(range.token), range: range.range)
        }
        let secret = theme.color(.variableSecret)
        for range in kinds.ranges(in: command) where range.token == .variableSecret {
            text.addAttributes([
                .foregroundColor: secret, .underlineStyle: NSUnderlineStyle([.single, .patternDot]).rawValue, .underlineColor: secret,
            ], range: range.range)
        }
        textView.textStorage?.setAttributedString(text)
        textView.font = font
    }
}

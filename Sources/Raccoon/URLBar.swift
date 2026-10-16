import AppKit
import Observation
import RaccoonDomain

/// `[method pop-up] [URL field] [Send]`, then the message line (design-system.md §6 URL bar).
final class URLBar: NSView, NSTextFieldDelegate {
    static let methods = ["GET", "POST", "PUT", "PATCH", "DELETE", "HEAD", "OPTIONS"]

    private let model: TabModel
    private let theme: ThemeEnvironment
    let methodButton = NSButton()
    let methodField = NSTextField()
    let urlField = FocusTextField()
    let urlBox = NSView()
    private let focusRing = NSView()
    private let fade = CAGradientLayer()
    let sendButton = NSButton()
    let messageLine = NSStackView()
    let messageGlyph = NSImageView()
    let messageText = NSTextField(wrappingLabelWithString: "")
    let messageClose = NSButton()

    init(model: TabModel, theme: ThemeEnvironment) {
        self.model = model
        self.theme = theme
        super.init(frame: .zero)
        buildMethod()
        buildURLField()
        buildSend()
        buildMessageLine()

        let row = NSStackView(views: [methodButton, urlBox, sendButton])
        row.spacing = 8
        row.alignment = .centerY
        let column = NSStackView(views: [row, messageLine])
        column.orientation = .vertical
        column.alignment = .leading
        column.spacing = 6
        column.translatesAutoresizingMaskIntoConstraints = false
        addSubview(column)
        NSLayoutConstraint.activate([
            column.topAnchor.constraint(equalTo: topAnchor, constant: 10),
            column.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -6),
            column.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            column.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            row.widthAnchor.constraint(equalTo: column.widthAnchor),
            // Indented to the URL field's leading edge: 12 + 84 + 8 = 104 pt from the pane.
            messageLine.leadingAnchor.constraint(equalTo: column.leadingAnchor, constant: 92),
            messageLine.trailingAnchor.constraint(lessThanOrEqualTo: column.trailingAnchor),
        ])
        render()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    // MARK: Method

    private func buildMethod() {
        methodButton.isBordered = false
        methodButton.wantsLayer = true
        style(methodButton)
        methodButton.target = self
        methodButton.action = #selector(showMethods)
        methodButton.setAccessibilityRole(.popUpButton)
        methodButton.setAccessibilityLabel("Method")
        methodButton.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            methodButton.heightAnchor.constraint(equalToConstant: 30),
            methodButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 84),
            methodButton.widthAnchor.constraint(lessThanOrEqualToConstant: 128),
        ])

        // "Other…" turns the label into this field until Return or a click elsewhere.
        methodField.isHidden = true
        methodField.isBordered = false
        methodField.drawsBackground = false
        methodField.focusRingType = .none
        methodField.font = .monospacedSystemFont(ofSize: 12, weight: .bold)
        methodField.textColor = theme.color(.methodOther)
        methodField.placeholderString = "METHOD"
        methodField.delegate = self
        methodField.setAccessibilityLabel("Method")
        methodField.translatesAutoresizingMaskIntoConstraints = false
        methodButton.addSubview(methodField)
        NSLayoutConstraint.activate([
            methodField.leadingAnchor.constraint(equalTo: methodButton.leadingAnchor, constant: 10),
            methodField.trailingAnchor.constraint(equalTo: methodButton.trailingAnchor, constant: -8),
            methodField.centerYAnchor.constraint(equalTo: methodButton.centerYAnchor),
        ])
    }

    var methodMenu: NSMenu {
        let menu = NSMenu()
        for method in Self.methods {
            let item = NSMenuItem(title: method, action: #selector(pickMethod), keyEquivalent: "")
            item.target = self
            item.attributedTitle = NSAttributedString(string: method, attributes: [
                .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .bold), .foregroundColor: theme.color(.method(method)),
            ])
            item.state = method == model.tab.definition.method ? .on : .off
            menu.addItem(item)
        }
        menu.addItem(.separator())
        let other = NSMenuItem(title: "Other…", action: #selector(editOtherMethod), keyEquivalent: "")
        other.target = self
        menu.addItem(other)
        return menu
    }

    @objc private func showMethods() {
        methodMenu.popUp(positioning: nil, at: NSPoint(x: 0, y: methodButton.bounds.height + 4), in: methodButton)
    }

    @objc func pickMethod(_ item: NSMenuItem) { model.setMethod(item.title) }

    @objc func editOtherMethod() {
        methodField.stringValue = Self.methods.contains(model.tab.definition.method) ? "" : model.tab.definition.method
        methodButton.attributedTitle = NSAttributedString()
        methodField.isHidden = false
        window?.makeFirstResponder(methodField)
    }

    private func methodTitle(_ method: String) -> NSAttributedString {
        let title = NSMutableAttributedString(string: method, attributes: [
            .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .bold), .foregroundColor: theme.color(.method(method)),
        ])
        title.append(NSAttributedString(string: "  ⌄", attributes: [
            .font: NSFont.systemFont(ofSize: 10), .foregroundColor: theme.color(.textTertiary), .baselineOffset: 2,
        ]))
        return title
    }

    // MARK: URL field

    private func buildURLField() {
        style(urlBox)
        urlBox.translatesAutoresizingMaskIntoConstraints = false
        urlBox.heightAnchor.constraint(equalToConstant: 30).isActive = true
        urlBox.setContentHuggingPriority(.defaultLow, for: .horizontal)
        urlBox.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        // A 3 pt ring at 35 % around the box while the field has focus.
        focusRing.wantsLayer = true
        focusRing.layer?.cornerRadius = 9
        focusRing.layer?.backgroundColor = theme.color(.focusRing).withAlphaComponent(0.35).cgColor
        focusRing.isHidden = true
        focusRing.translatesAutoresizingMaskIntoConstraints = false

        urlField.isBordered = false
        urlField.drawsBackground = false
        urlField.focusRingType = .none
        urlField.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        urlField.textColor = theme.color(.text)
        urlField.cell?.isScrollable = true
        urlField.cell?.wraps = false
        urlField.usesSingleLineMode = true
        urlField.placeholderAttributedString = NSAttributedString(string: "Enter a URL, or paste a curl command", attributes: [
            .font: NSFont.systemFont(ofSize: 13), .foregroundColor: theme.color(.textTertiary),
        ])
        urlField.delegate = self
        urlField.onFocus = { [weak self] in self?.showFocus(true) }
        urlField.setAccessibilityLabel("URL")
        urlField.wantsLayer = true
        // Fades the last 32 pt when the text runs past the field.
        fade.startPoint = CGPoint(x: 0, y: 0.5)
        fade.endPoint = CGPoint(x: 1, y: 0.5)
        fade.colors = [NSColor.black.cgColor, NSColor.black.cgColor, NSColor.clear.cgColor]
        urlField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        urlField.translatesAutoresizingMaskIntoConstraints = false
        urlBox.addSubview(urlField)
        NSLayoutConstraint.activate([
            urlField.leadingAnchor.constraint(equalTo: urlBox.leadingAnchor, constant: 10),
            urlField.trailingAnchor.constraint(equalTo: urlBox.trailingAnchor, constant: -10),
            urlField.centerYAnchor.constraint(equalTo: urlBox.centerYAnchor),
        ])
    }

    /// True when the text is wider than the field, so its end is faded.
    var isURLFaded: Bool { urlField.layer?.mask != nil }

    private func updateFade() {
        let overflows = urlField.attributedStringValue.size().width > urlField.bounds.width
        let editing = urlField.currentEditor() != nil
        guard overflows, !editing, urlField.bounds.width > 32 else {
            urlField.layer?.mask = nil
            return
        }
        fade.frame = urlField.bounds
        let solid = NSNumber(value: Double((urlField.bounds.width - 32) / urlField.bounds.width))
        fade.locations = [0, solid, 1]
        urlField.layer?.mask = fade
    }

    override func layout() {
        super.layout()
        if focusRing.superview == nil, let row = urlBox.superview {
            row.addSubview(focusRing, positioned: .below, relativeTo: urlBox)
            NSLayoutConstraint.activate([
                focusRing.leadingAnchor.constraint(equalTo: urlBox.leadingAnchor, constant: -3),
                focusRing.trailingAnchor.constraint(equalTo: urlBox.trailingAnchor, constant: 3),
                focusRing.topAnchor.constraint(equalTo: urlBox.topAnchor, constant: -3),
                focusRing.bottomAnchor.constraint(equalTo: urlBox.bottomAnchor, constant: 3),
            ])
        }
        updateFade()
    }

    /// `?`, `=` and `&` in `textSecondary`; the rest in `text`.
    private func urlTitle(_ text: String) -> NSAttributedString {
        let title = NSMutableAttributedString(string: text, attributes: [
            .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular), .foregroundColor: theme.color(.text),
        ])
        guard let mark = text.firstIndex(of: "?") else { return title }
        for index in text[mark...].indices where "?=&".contains(text[index]) {
            title.addAttribute(.foregroundColor, value: theme.color(.textSecondary), range: NSRange(index...index, in: text))
        }
        return title
    }

    // MARK: Send

    private func buildSend() {
        sendButton.isBordered = false
        sendButton.wantsLayer = true
        sendButton.layer?.cornerRadius = 6
        sendButton.layer?.backgroundColor = theme.color(.accent).cgColor
        sendButton.attributedTitle = NSAttributedString(string: "Send", attributes: [
            .font: NSFont.systemFont(ofSize: 13, weight: .semibold), .foregroundColor: theme.color(.textOnAccent),
        ])
        sendButton.target = self
        sendButton.action = #selector(send)
        sendButton.keyEquivalent = "\r"
        sendButton.keyEquivalentModifierMask = .command
        sendButton.toolTip = "Send (⌘↩)"
        sendButton.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            sendButton.heightAnchor.constraint(equalToConstant: 30),
            sendButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 76),
        ])
        sendButton.setContentHuggingPriority(.required, for: .horizontal)
    }

    @objc private func send() { model.send() }

    // MARK: Message line

    private func buildMessageLine() {
        messageLine.spacing = 6
        messageLine.alignment = .top
        messageGlyph.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            messageGlyph.widthAnchor.constraint(equalToConstant: 12),
            messageGlyph.heightAnchor.constraint(equalToConstant: 16),
        ])
        messageText.font = .systemFont(ofSize: 11)
        messageText.isSelectable = true
        messageClose.image = NSImage(systemSymbolName: "xmark", accessibilityDescription: "Dismiss")
        messageClose.isBordered = false
        messageClose.target = self
        messageClose.action = #selector(dismissMessage)
        messageClose.setAccessibilityLabel("Dismiss")
        messageLine.setViews([messageGlyph, messageText, messageClose], in: .leading)
    }

    @objc private func dismissMessage() { model.message = nil }

    // MARK: Edits and render

    func controlTextDidChange(_ notification: Notification) {
        guard notification.object as? NSTextField === urlField else { return }
        model.typeInURLBar(urlField.stringValue)
    }

    /// The ring shows on focus, not on the first keystroke, so the empty Draft shows it at launch.
    func showFocus(_ focused: Bool) {
        focusRing.isHidden = !focused
        urlBox.layer?.borderColor = theme.color(focused ? .focusRing : .border).cgColor
        updateFade()
    }

    func controlTextDidEndEditing(_ notification: Notification) {
        if notification.object as? NSTextField === methodField {
            model.setMethod(methodField.stringValue)
            methodField.isHidden = true
            render()
            return
        }
        showFocus(false)
        // The typed text was the source while editing; now show it as Params render it.
        render()
    }

    /// Redraws from the Tab, and again whenever it changes.
    func render() {
        withObservationTracking {
            let method = model.tab.definition.method
            if methodField.isHidden { methodButton.attributedTitle = methodTitle(method) }
            methodButton.setAccessibilityValue(method)
            // Never rewrite the field under the user's typing: the cursor would jump.
            if urlField.currentEditor() == nil { urlField.attributedStringValue = urlTitle(model.urlText) }
            updateFade()
            renderMessage(model.message)
        } onChange: { [weak self] in
            Task { @MainActor in self?.render() }
        }
    }

    private func renderMessage(_ message: MessageLine?) {
        messageLine.isHidden = message == nil
        guard let message else { return }
        let (text, token, symbol, isNote) = switch message {
        case .error(let text): (text, ColorToken.error, "exclamationmark.circle", false)
        case .note(let text): (text, ColorToken.textSecondary, "info.circle", true)
        }
        messageText.stringValue = text
        messageText.textColor = theme.color(token)
        messageGlyph.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 11, weight: .regular))
        messageGlyph.contentTintColor = theme.color(token)
        messageClose.contentTintColor = theme.color(token)
        // Only a note can be dismissed; an error stays until the next send or paste.
        messageClose.isHidden = !isNote
        if !isNote { NSAccessibility.post(element: messageText, notification: .announcementRequested, userInfo: [.announcement: text]) }
    }

    /// `backgroundElevated` with a 1 pt `border` and a 6 pt radius.
    private func style(_ view: NSView) {
        view.wantsLayer = true
        view.layer?.cornerRadius = 6
        view.layer?.borderWidth = 1
        view.layer?.borderColor = theme.color(.border).cgColor
        view.layer?.backgroundColor = theme.color(.backgroundElevated).cgColor
    }
}

/// Tells its owner when it takes focus; the end of editing comes through the delegate.
final class FocusTextField: NSTextField {
    var onFocus: () -> Void = {}

    override func becomeFirstResponder() -> Bool {
        let became = super.becomeFirstResponder()
        if became { onFocus() }
        return became
    }
}

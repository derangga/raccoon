import AppKit
import Observation
import RaccoonDomain

/// `[method pop-up] [URL field] [Send]`, then the message line (design-system.md §6 URL bar).
final class URLBar: NSView, NSTextFieldDelegate {
    static let methods = ["GET", "POST", "PUT", "PATCH", "DELETE", "HEAD", "OPTIONS"]

    private let model: TabModel
    private let theme: ThemeEnvironment
    let methodButton = NSButton()
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
        menu = NSMenu()
        menu?.addItem(MainMenu.copyAsCurl())
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
        return menu
    }

    @objc private func showMethods() {
        methodMenu.popUp(positioning: nil, at: NSPoint(x: 0, y: methodButton.bounds.height + 4), in: methodButton)
    }

    @objc func pickMethod(_ item: NSMenuItem) { model.setMethod(item.title) }

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
        urlField.onPaste = { [weak self] in self?.pasteCurl($0) ?? false }
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

    /// A pasted curl command fills the Tab; one Undo puts the Tab back. Anything else is not
    /// taken, so it is pasted into the field as text.
    func pasteCurl(_ text: String) -> Bool {
        let before = (definition: model.tab.definition, message: model.message)
        guard model.pasteInURLBar(text) else { return false }
        if model.tab.definition != before.definition {
            undoManager?.registerUndo(withTarget: self) { bar in MainActor.assumeIsolated { bar.restore(before) } }
            undoManager?.setActionName("Import curl")
        }
        showURL()
        return true
    }

    /// Puts the Tab and the line under the bar back, and registers the way forward, so Undo
    /// and Redo swap the same two states.
    private func restore(_ state: (definition: RequestDefinition, message: MessageLine?)) {
        let current = (definition: model.tab.definition, message: model.message)
        undoManager?.registerUndo(withTarget: self) { bar in MainActor.assumeIsolated { bar.restore(current) } }
        undoManager?.setActionName("Import curl")
        model.tab.definition = state.definition
        model.message = state.message
        showURL()
    }

    /// The field shows the Tab's URL even while it has focus, with the caret at the end: setting
    /// the text while editing would select all of it.
    private func showURL() {
        urlField.stringValue = model.urlText
        if let editor = urlField.currentEditor() { editor.selectedRange = NSRange(location: (editor.string as NSString).length, length: 0) }
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
        sendButton.layer?.borderWidth = 1
        sendButton.target = self
        sendButton.action = #selector(sendOrCancel)
        sendButton.keyEquivalentModifierMask = .command
        sendButton.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            sendButton.heightAnchor.constraint(equalToConstant: 30),
            sendButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 76),
        ])
        sendButton.setContentHuggingPriority(.required, for: .horizontal)
    }

    /// Send, or while sending, Cancel: `backgroundElevated`, `border`, `text`, on ⌘. instead of
    /// ⌘↩, so a second ⌘↩ while sending does nothing.
    private func renderSend(sending: Bool) {
        let (title, key, fill, edge, ink) = sending
            ? ("Cancel", ".", ColorToken.backgroundElevated, ColorToken.border, ColorToken.text)
            : ("Send", "\r", .accent, .accent, .textOnAccent)
        sendButton.attributedTitle = NSAttributedString(string: title, attributes: [
            .font: NSFont.systemFont(ofSize: 13, weight: .semibold), .foregroundColor: theme.color(ink),
        ])
        sendButton.layer?.backgroundColor = theme.color(fill).cgColor
        sendButton.layer?.borderColor = theme.color(edge).cgColor
        sendButton.keyEquivalent = key
        sendButton.toolTip = sending ? "Cancel (⌘.)" : "Send (⌘↩)"
    }

    private var isSending: Bool {
        if case .sending = model.tab.response { true } else { false }
    }

    @objc private func sendOrCancel() {
        if isSending { model.cancel() } else { model.send() }
    }

    // MARK: Message line

    private func buildMessageLine() {
        messageLine.spacing = 6
        messageLine.alignment = .top
        // Glyph and ✕ are one 16 pt line tall, so on a top-aligned line both center on the first line.
        messageGlyph.translatesAutoresizingMaskIntoConstraints = false
        messageClose.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            messageGlyph.widthAnchor.constraint(equalToConstant: 12),
            messageGlyph.heightAnchor.constraint(equalToConstant: 16),
            messageClose.heightAnchor.constraint(equalToConstant: 16),
        ])
        messageText.font = .systemFont(ofSize: 11)
        messageText.isSelectable = true
        messageClose.image = NSImage(systemSymbolName: "xmark", accessibilityDescription: "Dismiss")?
            .withSymbolConfiguration(.init(pointSize: 11, weight: .regular))
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
        urlBox.layer?.borderColor = theme.color(model.isURLInvalid ? .error : focused ? .focusRing : .border).cgColor
        updateFade()
    }

    func controlTextDidEndEditing(_ notification: Notification) {
        showFocus(false)
        // The typed text was the source while editing; now show it as Params render it.
        render()
    }

    /// Redraws from the Tab, and again whenever it changes.
    func render() {
        withObservationTracking {
            let method = model.tab.definition.method
            methodButton.attributedTitle = methodTitle(method)
            methodButton.setAccessibilityValue(method)
            // Never rewrite the field under the user's typing: the cursor would jump.
            if urlField.currentEditor() == nil { urlField.attributedStringValue = urlTitle(model.urlText) }
            updateFade()
            renderSend(sending: isSending)
            showFocus(urlField.currentEditor() != nil)
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
    /// True when the owner took the pasted text, so the field inserts nothing.
    var onPaste: (String) -> Bool = { _ in false }

    override class var cellClass: AnyClass? {
        get { PasteFieldCell.self }
        set {}
    }

    override func becomeFirstResponder() -> Bool {
        let became = super.becomeFirstResponder()
        if became { onFocus() }
        return became
    }
}

/// Hands the field a field editor that offers a paste to the field first. A single-line field
/// editor turns the newlines of a multi-line paste into spaces, so a curl command has to be
/// read before it is inserted.
final class PasteFieldCell: NSTextFieldCell {
    private let editor: PasteFieldEditor = {
        let editor = PasteFieldEditor()
        editor.isFieldEditor = true
        return editor
    }()

    override func fieldEditor(for controlView: NSView) -> NSTextView? {
        editor.onPaste = { [weak controlView] in (controlView as? FocusTextField)?.onPaste($0) ?? false }
        return editor
    }
}

final class PasteFieldEditor: NSTextView {
    var onPaste: (String) -> Bool = { _ in false }
    var pasteboard = NSPasteboard.general

    override func paste(_ sender: Any?) {
        if let text = pasteboard.string(forType: .string), onPaste(text) { return }
        super.paste(sender)
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = super.menu(for: event) ?? NSMenu()
        menu.addItem(.separator())
        menu.addItem(MainMenu.copyAsCurl())
        return menu
    }
}

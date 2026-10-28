import AppKit
import RaccoonDomain

/// The Settings section: two checkboxes, each with its hint (design-system.md §6 Request Settings).
/// No compression row: URLSession always asks for and decodes gzip (Open UI question 10).
final class SettingsPane: NSView {
    let checkboxes: [NSButton]
    let insecureTLSHint = NSTextField(wrappingLabelWithString: "Accept certificates the system does not trust, for this Request only.")
    var onChange: (RequestSettings) -> Void = { _ in }

    init(theme: ThemeEnvironment) {
        checkboxes = ["Allow insecure TLS", "Follow redirects"].map { NSButton(checkboxWithTitle: $0, target: nil, action: nil) }
        super.init(frame: .zero)
        for box in checkboxes {
            box.target = self
            box.action = #selector(toggled)
        }
        insecureTLSHint.font = .systemFont(ofSize: 11)
        theme.paint(insecureTLSHint) { $0.textColor = $1.color(.textTertiary) }
        let insecure = NSStackView(views: [checkboxes[0], insecureTLSHint])
        insecure.orientation = .vertical
        insecure.alignment = .leading
        insecure.spacing = 2
        let column = NSStackView(views: [insecure, checkboxes[1]])
        column.orientation = .vertical
        column.alignment = .leading
        column.spacing = 10
        column.translatesAutoresizingMaskIntoConstraints = false
        addSubview(column)
        NSLayoutConstraint.activate([
            column.topAnchor.constraint(equalTo: topAnchor),
            column.leadingAnchor.constraint(equalTo: leadingAnchor),
            column.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor),
            // The hint lines up with the checkbox title, not the box.
            insecureTLSHint.leadingAnchor.constraint(equalTo: insecure.leadingAnchor, constant: 20),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func setSettings(_ settings: RequestSettings) {
        checkboxes[0].state = settings.allowsInsecureTLS ? .on : .off
        checkboxes[1].state = settings.followsRedirects ? .on : .off
    }

    @objc private func toggled() {
        onChange(RequestSettings(allowsInsecureTLS: checkboxes[0].state == .on, followsRedirects: checkboxes[1].state == .on))
    }
}

/// The Auth section (design-system.md §6 Auth section): a 240 pt left column with the Auth type
/// pop-up and the paragraph saying what the send does, a 1 pt rule, and the scheme's fields on
/// the right. Below 600 pt of its own width the columns stack. The pane keeps no values of its
/// own: `auth` is the Tab's, so another Tab, or the same one after a switch, shows what it holds.
final class AuthPane: NSView, NSTextFieldDelegate {
    /// Two columns need 597 pt (design-system.md), so 600 pt is where the field would shrink.
    static let stackedBelow: CGFloat = 600
    private static let schemes: [(title: String, auth: Auth)] = [
        ("None", .none), ("Basic Auth", .basic(user: "", password: "")), ("Bearer Token", .bearer(token: "")),
    ]

    private let theme: ThemeEnvironment
    let typeButton = PopButton()
    let note = NSTextField(wrappingLabelWithString: "")
    let heading = NSTextField(labelWithString: "")
    let username = VariableField()
    let password = NSSecureTextField()
    /// Shown in place of the bullets when the password holds a `{{name}}`, so the name is readable.
    let passwordVariable = VariableField()
    let token = VariableField()
    private(set) var basicFields = NSGridView()
    private(set) var bearerFields = NSGridView()
    let leftColumn = NSStackView()
    let rightColumn = NSStackView()
    let rule = NSBox()
    /// The right side while Auth is None: the symbol, "No Auth" and how to add one, centered in the
    /// area right of the rule (under it when stacked).
    let emptyArea = NSView()
    let emptyTitle = NSTextField(labelWithString: "No Auth")
    let emptyMessage = NSTextField(wrappingLabelWithString: "Pick Basic Auth or Bearer Token under Auth type to add one.")
    private(set) var isStacked = false
    private var wideConstraints: [NSLayoutConstraint] = []
    private var stackedConstraints: [NSLayoutConstraint] = []
    private let chevron = NSImageView()
    var onChange: (Auth) -> Void = { _ in }

    private var auth = Auth.none
    private var headers: [Row] = []

    init(theme: ThemeEnvironment) {
        self.theme = theme
        super.init(frame: .zero)
        buildLeft()
        buildRight()
        buildEmpty()
        rule.boxType = .custom
        rule.borderWidth = 0
        rule.contentViewMargins = .zero
        theme.paint(rule) { $0.fillColor = $1.color(.border) }
        for view in [emptyArea, leftColumn, rule, rightColumn] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        constrain()
        theme.paint(self) { pane, _ in pane.restyle() }
        setAuth(.none)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    // MARK: Layout

    private func buildLeft() {
        let label = NSTextField(labelWithString: "Auth type")
        label.font = .systemFont(ofSize: 12, weight: .semibold)
        note.font = .systemFont(ofSize: 12)
        note.preferredMaxLayoutWidth = 240
        theme.paint(label) { $0.textColor = $1.color(.textSecondary) }
        theme.paint(note) { $0.textColor = $1.color(.textSecondary) }

        typeButton.isBordered = false
        typeButton.alignment = .left
        typeButton.wantsLayer = true
        typeButton.layer?.cornerRadius = 6
        typeButton.layer?.borderWidth = 1
        typeButton.target = self
        typeButton.action = #selector(showTypes)
        typeButton.setAccessibilityRole(.popUpButton)
        typeButton.setAccessibilityLabel("Auth type")
        chevron.image = NSImage(systemSymbolName: "chevron.down", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 9, weight: .semibold))
        chevron.translatesAutoresizingMaskIntoConstraints = false
        typeButton.addSubview(chevron)
        typeButton.translatesAutoresizingMaskIntoConstraints = false

        leftColumn.orientation = .vertical
        leftColumn.alignment = .leading
        leftColumn.spacing = 6
        for view in [label, typeButton, note] { leftColumn.addArrangedSubview(view) }
        NSLayoutConstraint.activate([
            leftColumn.widthAnchor.constraint(equalToConstant: 240),
            typeButton.widthAnchor.constraint(equalToConstant: 240),
            typeButton.heightAnchor.constraint(equalToConstant: 28),
            note.widthAnchor.constraint(equalToConstant: 240),
            chevron.trailingAnchor.constraint(equalTo: typeButton.trailingAnchor, constant: -8),
            chevron.centerYAnchor.constraint(equalTo: typeButton.centerYAnchor),
        ])
    }

    private func buildRight() {
        heading.font = .systemFont(ofSize: 17)
        theme.paint(heading) { $0.textColor = $1.color(.text) }
        for field in [username, password, passwordVariable, token] {
            field.isBordered = false
            field.drawsBackground = false
            field.focusRingType = .none
            field.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
            theme.paint(field) { field, theme in
                field.textColor = theme.color(.text)
                field.placeholderAttributedString = NSAttributedString(string: field.placeholderString ?? "", attributes: [
                    .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular), .foregroundColor: theme.color(.textTertiary),
                ])
            }
            field.cell?.isScrollable = true
            field.cell?.wraps = false
            field.delegate = self
            field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        }
        for field in [username, passwordVariable, token] { field.theme = theme }
        username.placeholderString = "Username"
        for field in [password, passwordVariable] { field.placeholderString = "Password" }
        token.placeholderString = "Token"
        let secret = NSView()
        for field in [password, passwordVariable] { fill(secret, with: field) }
        basicFields = grid([("Username", boxed(username)), ("Password", boxed(secret))])
        bearerFields = grid([("Token", boxed(token))])

        rightColumn.orientation = .vertical
        rightColumn.alignment = .leading
        rightColumn.spacing = 14
        for view in [heading, basicFields, bearerFields] { rightColumn.addArrangedSubview(view) }
        NSLayoutConstraint.activate([
            basicFields.trailingAnchor.constraint(lessThanOrEqualTo: rightColumn.trailingAnchor),
            bearerFields.trailingAnchor.constraint(lessThanOrEqualTo: rightColumn.trailingAnchor),
        ])
    }

    private func buildEmpty() {
        let glyph = NSImageView(image: NSImage(systemSymbolName: "lock.open", accessibilityDescription: nil)!)
        glyph.symbolConfiguration = .init(pointSize: 20, weight: .regular)
        emptyTitle.font = .systemFont(ofSize: 13, weight: .semibold)
        emptyMessage.font = .systemFont(ofSize: 12)
        emptyMessage.alignment = .center
        emptyMessage.preferredMaxLayoutWidth = 260
        theme.paint(glyph) { $0.contentTintColor = $1.color(.textTertiary) }
        theme.paint(emptyTitle) { $0.textColor = $1.color(.textSecondary) }
        theme.paint(emptyMessage) { $0.textColor = $1.color(.textTertiary) }
        let stack = NSStackView(views: [glyph, emptyTitle, emptyMessage])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        emptyArea.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: emptyArea.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: emptyArea.centerYAnchor),
            stack.widthAnchor.constraint(lessThanOrEqualTo: emptyArea.widthAnchor),
        ])
    }

    /// Both layouts are built once and one set is active, so crossing 600 pt moves views and
    /// touches no value.
    private func constrain() {
        let pad: CGFloat = 16
        NSLayoutConstraint.activate([
            leftColumn.topAnchor.constraint(equalTo: topAnchor, constant: pad),
            leftColumn.leadingAnchor.constraint(equalTo: leadingAnchor, constant: pad),
            rightColumn.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -pad),
            emptyArea.trailingAnchor.constraint(equalTo: trailingAnchor),
            emptyArea.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        // The rule spans the pane's whole height, which the editor fixes.
        wideConstraints = [
            rule.topAnchor.constraint(equalTo: topAnchor),
            rule.bottomAnchor.constraint(equalTo: bottomAnchor),
            rule.leadingAnchor.constraint(equalTo: leftColumn.trailingAnchor, constant: pad),
            rule.widthAnchor.constraint(equalToConstant: 1),
            emptyArea.topAnchor.constraint(equalTo: topAnchor),
            emptyArea.leadingAnchor.constraint(equalTo: rule.trailingAnchor),
            rightColumn.topAnchor.constraint(equalTo: topAnchor, constant: pad),
            rightColumn.leadingAnchor.constraint(equalTo: rule.trailingAnchor, constant: pad),
        ]
        stackedConstraints = [
            rule.topAnchor.constraint(equalTo: leftColumn.bottomAnchor, constant: pad),
            rule.leadingAnchor.constraint(equalTo: leadingAnchor, constant: pad),
            rule.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -pad),
            rule.heightAnchor.constraint(equalToConstant: 1),
            emptyArea.topAnchor.constraint(equalTo: rule.bottomAnchor),
            emptyArea.leadingAnchor.constraint(equalTo: leadingAnchor),
            rightColumn.topAnchor.constraint(equalTo: rule.bottomAnchor, constant: pad),
            rightColumn.leadingAnchor.constraint(equalTo: leadingAnchor, constant: pad),
        ]
        NSLayoutConstraint.activate(wideConstraints)
    }

    /// The pane's own width decides, not the window's. Switched when the width is set, so the
    /// constraints that lay the columns out are the ones for the width they get.
    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        let stacked = newSize.width < Self.stackedBelow
        guard stacked != isStacked else { return }
        isStacked = stacked
        NSLayoutConstraint.deactivate(stacked ? wideConstraints : stackedConstraints)
        NSLayoutConstraint.activate(stacked ? stackedConstraints : wideConstraints)
    }

    /// Labels left-aligned in `text` at 80 pt, then the fields, up to 320 pt wide, rows 36 pt apart.
    private func grid(_ rows: [(String, NSView)]) -> NSGridView {
        let grid = NSGridView(views: rows.map { title, field in
            let label = NSTextField(labelWithString: title)
            label.font = .systemFont(ofSize: 13)
            theme.paint(label) { $0.textColor = $1.color(.text) }
            field.widthAnchor.constraint(lessThanOrEqualToConstant: 320).isActive = true
            let preferred = field.widthAnchor.constraint(equalToConstant: 320)
            preferred.priority = .init(700)
            preferred.isActive = true
            return [label, field]
        })
        grid.column(at: 0).width = 80
        grid.column(at: 0).xPlacement = .leading
        grid.column(at: 1).xPlacement = .leading
        grid.columnSpacing = 12
        grid.rowSpacing = 10
        grid.yPlacement = .center
        return grid
    }

    /// 26 pt, `backgroundElevated`, a 1 pt `border` and a 6 pt radius around a borderless field.
    private func boxed(_ content: NSView) -> NSView {
        let box = NSView()
        box.wantsLayer = true
        box.layer?.cornerRadius = 6
        box.layer?.borderWidth = 1
        theme.paint(box) { box, theme in
            box.layer?.borderColor = theme.color(.border).cgColor
            box.layer?.backgroundColor = theme.color(.backgroundElevated).cgColor
        }
        box.translatesAutoresizingMaskIntoConstraints = false
        box.heightAnchor.constraint(equalToConstant: 26).isActive = true
        content.translatesAutoresizingMaskIntoConstraints = false
        box.addSubview(content)
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: box.leadingAnchor, constant: 8),
            content.trailingAnchor.constraint(equalTo: box.trailingAnchor, constant: -8),
            content.centerYAnchor.constraint(equalTo: box.centerYAnchor),
        ])
        return box
    }

    private func fill(_ container: NSView, with field: NSView) {
        field.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(field)
        NSLayoutConstraint.activate([
            field.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            field.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            field.topAnchor.constraint(equalTo: container.topAnchor),
            field.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
    }

    // MARK: Pop-up

    var typeMenu: NSMenu {
        let menu = NSMenu()
        for (index, scheme) in Self.schemes.enumerated() {
            let item = NSMenuItem(title: scheme.title, action: #selector(pickScheme), keyEquivalent: "")
            item.target = self
            item.tag = index
            item.state = index == Self.index(of: auth) ? .on : .off
            menu.addItem(item)
        }
        return menu
    }

    private static func index(of auth: Auth) -> Int {
        switch auth {
        case .none: 0
        case .basic: 1
        case .bearer: 2
        }
    }

    @objc private func showTypes() { typeMenu.popUp(positioning: nil, at: NSPoint(x: 0, y: typeButton.bounds.height + 4), in: typeButton) }

    @objc private func pickScheme(_ item: NSMenuItem) {
        let picked = Self.schemes[item.tag].auth
        guard Self.index(of: picked) != Self.index(of: auth) else { return }
        change(to: picked)
    }

    /// One undo step: the old Auth comes back with what was typed, and undoing registers the redo.
    private func change(to new: Auth) {
        let old = auth
        onChange(new)
        setAuth(new)
        undoManager?.registerUndo(withTarget: self) { $0.change(to: old) }
        undoManager?.setActionName("Auth Type")
    }

    // MARK: Content

    private func restyle() {
        let title = NSMutableParagraphStyle()
        title.alignment = .left
        title.firstLineHeadIndent = 10
        typeButton.attributedTitle = NSAttributedString(string: Self.schemes[Self.index(of: auth)].title, attributes: [
            .font: NSFont.systemFont(ofSize: 13), .foregroundColor: theme.color(.text), .paragraphStyle: title,
        ])
        typeButton.layer?.borderColor = theme.color(.border).cgColor
        typeButton.layer?.backgroundColor = theme.color(.backgroundElevated).cgColor
        chevron.contentTintColor = theme.color(.textTertiary)
    }

    private static func holdsVariable(_ text: String) -> Bool { text.contains(/\{\{[^{}]+\}\}/) }

    /// Shows `auth`, the Tab's, and the paragraph for it and the Headers rows. Every field is set
    /// from it, the ones of another scheme to empty, so nothing typed elsewhere shows here.
    func setAuth(_ auth: Auth, headers: [Row]? = nil) {
        self.auth = auth
        if let headers { self.headers = headers }
        let values: (user: String, password: String, token: String) = switch auth {
        case .none: ("", "", "")
        case .basic(let user, let password): (user, password, "")
        case .bearer(let token): ("", "", token)
        }
        restyle()
        note.stringValue = AuthNote.text(auth, headers: self.headers)
        heading.stringValue = Self.schemes[Self.index(of: auth)].title
        heading.isHidden = auth == .none
        emptyArea.isHidden = auth != .none
        basicFields.isHidden = Self.index(of: auth) != 1
        bearerFields.isHidden = Self.index(of: auth) != 2
        // Never rewrite a field under the user's typing: the cursor would jump.
        for (field, value) in [(username, values.user), (password, values.password), (passwordVariable, values.password), (token, values.token)]
            where field.currentEditor() == nil {
            field.stringValue = value
            (field as? VariableField)?.highlight()
        }
        // Swapped only while neither is being edited, so typing `{{` never moves the focus.
        if password.currentEditor() == nil, passwordVariable.currentEditor() == nil {
            let named = Self.holdsVariable(values.password)
            password.isHidden = named
            passwordVariable.isHidden = !named
        }
    }

    /// The password field shows bullets, so it is never coloured.
    func setKinds(_ kinds: VariableKinds) {
        for field in [username, passwordVariable, token] { field.kinds = kinds }
    }

    func controlTextDidChange(_ notification: Notification) {
        guard let field = notification.object as? NSTextField else { return }
        switch (auth, field) {
        case (.basic(_, let password), username): auth = .basic(user: field.stringValue, password: password)
        case (.basic(let user, _), password), (.basic(let user, _), passwordVariable): auth = .basic(user: user, password: field.stringValue)
        case (.bearer, token): auth = .bearer(token: field.stringValue)
        default: return
        }
        onChange(auth)
    }
}

private extension NSLayoutConstraint {
    func withPriority(_ priority: NSLayoutConstraint.Priority) -> NSLayoutConstraint {
        self.priority = priority
        return self
    }
}

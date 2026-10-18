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
        insecureTLSHint.textColor = theme.color(.textTertiary)
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

/// The Auth section: None · Basic · Bearer, then the scheme's fields (design-system.md §6 Auth
/// section). A scheme switched away from keeps its values here, so switching back restores them.
final class AuthPane: NSView, NSTextFieldDelegate {
    private let theme: ThemeEnvironment
    let scheme: SegmentedControl
    let noneNote = NSTextField(labelWithString: "No Authorization header is added.")
    let username = NSTextField()
    let password = NSSecureTextField()
    /// Shown in place of the bullets when the password holds a `{{name}}`, so the name is readable.
    let passwordVariable = NSTextField()
    let token = NSTextField()
    private(set) var basicFields = NSGridView()
    private(set) var bearerFields = NSGridView()
    var onChange: (Auth) -> Void = { _ in }

    private var basic = (user: "", password: "")
    private var bearer = ""

    init(theme: ThemeEnvironment) {
        self.theme = theme
        scheme = SegmentedControl(labels: ["None", "Basic", "Bearer"], theme: theme)
        super.init(frame: .zero)
        let typeLabel = NSTextField(labelWithString: "Type")
        for label in [typeLabel, noneNote] {
            label.font = .systemFont(ofSize: 11)
            label.textColor = theme.color(.textTertiary)
        }
        scheme.target = self
        scheme.action = #selector(schemePicked)
        scheme.selectedSegment = 0
        let row = NSStackView(views: [typeLabel, scheme, noneNote])
        row.spacing = 8

        for field in [username, password, passwordVariable, token] {
            field.isBordered = false
            field.drawsBackground = false
            field.focusRingType = .none
            field.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
            field.textColor = theme.color(.text)
            field.cell?.isScrollable = true
            field.cell?.wraps = false
            field.delegate = self
        }
        let secret = NSView()
        for field in [password, passwordVariable] { fill(secret, with: field) }
        basicFields = grid([("Username", boxed(username)), ("Password", boxed(secret))])
        bearerFields = grid([("Token", boxed(token))])

        let column = NSStackView(views: [row, basicFields, bearerFields])
        column.orientation = .vertical
        column.alignment = .leading
        column.spacing = 12
        column.translatesAutoresizingMaskIntoConstraints = false
        addSubview(column)
        NSLayoutConstraint.activate([
            column.topAnchor.constraint(equalTo: topAnchor),
            column.leadingAnchor.constraint(equalTo: leadingAnchor),
            column.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor),
            basicFields.widthAnchor.constraint(equalTo: column.widthAnchor),
            bearerFields.widthAnchor.constraint(equalTo: column.widthAnchor),
            column.widthAnchor.constraint(equalTo: widthAnchor).withPriority(.defaultLow),
        ])
        setAuth(.none)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// Labels right-aligned in `textSecondary` at 80 pt, then the fields, up to 360 pt wide.
    private func grid(_ rows: [(String, NSView)]) -> NSGridView {
        let grid = NSGridView(views: rows.map { title, field in
            let label = NSTextField(labelWithString: title)
            label.textColor = theme.color(.textSecondary)
            label.alignment = .right
            field.widthAnchor.constraint(lessThanOrEqualToConstant: 360).isActive = true
            return [label, field]
        })
        grid.column(at: 0).width = 80
        grid.column(at: 0).xPlacement = .trailing
        grid.columnSpacing = 12
        grid.rowSpacing = 8
        grid.yPlacement = .center
        return grid
    }

    /// 26 pt, `backgroundElevated`, a 1 pt `border` and a 6 pt radius around a borderless field.
    private func boxed(_ content: NSView) -> NSView {
        let box = NSView()
        box.wantsLayer = true
        box.layer?.cornerRadius = 6
        box.layer?.borderWidth = 1
        box.layer?.borderColor = theme.color(.border).cgColor
        box.layer?.backgroundColor = theme.color(.backgroundElevated).cgColor
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

    private static func holdsVariable(_ text: String) -> Bool { text.contains(/\{\{[^{}]+\}\}/) }

    func setAuth(_ auth: Auth) {
        switch auth {
        case .none: scheme.selectedSegment = 0
        case .basic(let user, let password):
            scheme.selectedSegment = 1
            basic = (user, password)
        case .bearer(let token):
            scheme.selectedSegment = 2
            bearer = token
        }
        noneNote.isHidden = scheme.selectedSegment != 0
        basicFields.isHidden = scheme.selectedSegment != 1
        bearerFields.isHidden = scheme.selectedSegment != 2
        // Never rewrite a field under the user's typing: the cursor would jump.
        for (field, value) in [(username, basic.user), (password, basic.password), (passwordVariable, basic.password), (token, bearer)]
            where field.currentEditor() == nil {
            field.stringValue = value
        }
        // Swapped only while neither is being edited, so typing `{{` never moves the focus.
        if password.currentEditor() == nil, passwordVariable.currentEditor() == nil {
            let named = Self.holdsVariable(basic.password)
            password.isHidden = named
            passwordVariable.isHidden = !named
        }
    }

    private var auth: Auth {
        switch scheme.selectedSegment {
        case 1: .basic(user: basic.user, password: basic.password)
        case 2: .bearer(token: bearer)
        default: .none
        }
    }

    @objc private func schemePicked() {
        onChange(auth)
        setAuth(auth)
    }

    func controlTextDidChange(_ notification: Notification) {
        guard let field = notification.object as? NSTextField else { return }
        switch field {
        case username: basic.user = field.stringValue
        case password, passwordVariable: basic.password = field.stringValue
        case token: bearer = field.stringValue
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

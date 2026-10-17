import AppKit
import Observation
import RaccoonDomain

enum EditorSection: CaseIterable {
    case params, headers, body, auth, cookies, settings

    var name: String {
        switch self {
        case .params: "Params"
        case .headers: "Headers"
        case .body: "Body"
        case .auth: "Auth"
        case .cookies: "Cookies"
        case .settings: "Settings"
        }
    }

    /// What follows the name: a row count (Disabled Rows too, none for no rows) or
    /// the Auth scheme.
    func detail(in definition: RequestDefinition) -> String? {
        func count(_ rows: [Row]) -> String? { rows.isEmpty ? nil : "\(rows.count)" }
        return switch self {
        case .params: count(definition.params)
        case .headers: count(definition.headers)
        case .cookies: count(definition.cookies)
        // Body shows no Body Type: its pane's pop-ups already name it.
        case .body, .settings: nil
        case .auth:
            switch definition.auth {
            case .none: nil
            case .basic: "Basic"
            case .bearer: "Bearer"
            }
        }
    }

    func title(in definition: RequestDefinition) -> String {
        detail(in: definition).map { "\(name) \($0)" } ?? name
    }
}

/// The section bar over one pane per section (surfaces.md §1 RequestEditor). Params, Headers
/// and Cookies are key/value tables writing the Tab's definition.
final class RequestEditor: NSView {
    private let model: TabModel
    private let theme: ThemeEnvironment
    private(set) var selected = EditorSection.params
    private var buttons: [EditorSection: SectionButton] = [:]
    private var panes: [EditorSection: NSView] = [:]
    private var tables: [EditorSection: KeyValueTable] = [:]
    let settingsPane: SettingsPane
    let authPane: AuthPane
    let bodyPane: BodyPane

    init(model: TabModel, theme: ThemeEnvironment) {
        self.model = model
        self.theme = theme
        settingsPane = SettingsPane(theme: theme)
        authPane = AuthPane(theme: theme)
        bodyPane = BodyPane(model: model, theme: theme)
        super.init(frame: .zero)
        authPane.onChange = { [weak self] in self?.model.tab.definition.auth = $0 }
        settingsPane.onChange = { [weak self] in self?.model.tab.definition.settings = $0 }

        let bar = NSStackView()
        bar.spacing = 2
        bar.edgeInsets = NSEdgeInsets(top: 4, left: 12, bottom: 0, right: 12)
        bar.alignment = .bottom
        bar.setAccessibilityRole(.tabGroup)
        bar.setAccessibilityLabel("Request sections")
        let rule = NSBox()
        rule.boxType = .custom
        rule.borderWidth = 0
        rule.fillColor = theme.color(.border)

        let paneArea = NSView()
        for section in EditorSection.allCases {
            let button = SectionButton(theme: theme, target: self, action: #selector(sectionClicked))
            buttons[section] = button
            bar.addArrangedSubview(button)

            let pane: NSView
            if let rows = Self.rows(section) {
                let table = KeyValueTable(theme: theme)
                table.onChange = { [weak self] in self?.model.tab.definition[keyPath: rows] = $0 }
                tables[section] = table
                pane = table
            } else if section == .settings {
                pane = settingsPane
            } else if section == .auth {
                pane = authPane
            } else if section == .body {
                pane = bodyPane
            } else {
                pane = NSView()
            }
            panes[section] = pane
            pane.translatesAutoresizingMaskIntoConstraints = false
            paneArea.addSubview(pane)
            NSLayoutConstraint.activate([
                pane.leadingAnchor.constraint(equalTo: paneArea.leadingAnchor, constant: 12),
                pane.trailingAnchor.constraint(equalTo: paneArea.trailingAnchor, constant: -12),
                pane.topAnchor.constraint(equalTo: paneArea.topAnchor, constant: 8),
                pane.bottomAnchor.constraint(lessThanOrEqualTo: paneArea.bottomAnchor, constant: -8),
            ])
            // A table hugs its rows; any other pane fills the area.
            if !(pane is KeyValueTable) { pane.bottomAnchor.constraint(equalTo: paneArea.bottomAnchor, constant: -8).isActive = true }
            pane.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        }

        for view in [bar, rule, paneArea] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        NSLayoutConstraint.activate([
            bar.topAnchor.constraint(equalTo: topAnchor),
            bar.leadingAnchor.constraint(equalTo: leadingAnchor),
            bar.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor),
            bar.heightAnchor.constraint(equalToConstant: 32),
            rule.topAnchor.constraint(equalTo: bar.bottomAnchor, constant: -1),
            rule.leadingAnchor.constraint(equalTo: leadingAnchor),
            rule.trailingAnchor.constraint(equalTo: trailingAnchor),
            rule.heightAnchor.constraint(equalToConstant: 1),
            paneArea.topAnchor.constraint(equalTo: rule.bottomAnchor),
            paneArea.leadingAnchor.constraint(equalTo: leadingAnchor),
            paneArea.trailingAnchor.constraint(equalTo: trailingAnchor),
            paneArea.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        // The bar sits above the rule, so the selected underline covers it.
        addSubview(bar, positioned: .above, relativeTo: rule)
        select(.params)
        render()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    private static func rows(_ section: EditorSection) -> WritableKeyPath<RequestDefinition, [Row]>? {
        switch section {
        case .params: \.params
        case .headers: \.headers
        case .cookies: \.cookies
        case .body, .auth, .settings: nil
        }
    }

    func table(_ section: EditorSection) -> KeyValueTable {
        guard let table = tables[section] else { preconditionFailure("\(section) has no key/value table") }
        return table
    }

    func select(_ section: EditorSection) {
        selected = section
        for (each, pane) in panes { pane.isHidden = each != section }
        for (each, button) in buttons { button.isOn = each == section }
    }

    @objc private func sectionClicked(_ sender: SectionButton) {
        guard let section = buttons.first(where: { $0.value === sender })?.key else { return }
        select(section)
    }

    /// Redraws from the Tab's definition, and again whenever it changes.
    func render() {
        withObservationTracking {
            let definition = model.tab.definition
            for (section, button) in buttons {
                button.set(name: section.name, detail: section.detail(in: definition))
            }
            for (section, table) in tables {
                if let rows = Self.rows(section) { table.setRows(definition[keyPath: rows]) }
            }
            // An empty Draft or an invalid URL has no host yet, so nothing to show.
            let resolved = try? VariableResolver.resolve(definition)
            settingsPane.setSettings(definition.settings)
            authPane.setAuth(definition.auth)
            bodyPane.setBody(definition.body)
            table(.headers).setAutomaticRows(resolved.map(AutomaticHeaders.rows) ?? [])
        } onChange: { [weak self] in
            Task { @MainActor in self?.render() }
        }
    }
}

/// One section in the bar: 28 pt, the name, then its detail in tabular `textTertiary`, and a 2 pt
/// `accent` underline when selected.
final class SectionButton: NSButton {
    private let theme: ThemeEnvironment
    private var name = ""
    private var detail: String?
    var isOn = false {
        didSet {
            redraw()
            setAccessibilityValue(isOn)
        }
    }

    init(theme: ThemeEnvironment, target: AnyObject, action: Selector) {
        self.theme = theme
        super.init(frame: .zero)
        self.target = target
        self.action = action
        isBordered = false
        setButtonType(.momentaryChange)
        setAccessibilityRole(.radioButton)
        translatesAutoresizingMaskIntoConstraints = false
        heightAnchor.constraint(equalToConstant: 28).isActive = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func set(name: String, detail: String?) {
        guard (name, detail) != (self.name, self.detail) else { return }
        (self.name, self.detail) = (name, detail)
        redraw()
    }

    private func redraw() {
        let title = NSMutableAttributedString(string: name, attributes: [
            .font: NSFont.systemFont(ofSize: 13, weight: isOn ? .semibold : .regular),
            .foregroundColor: theme.color(isOn ? .text : .textSecondary),
        ])
        if let detail {
            title.append(NSAttributedString(string: " \(detail)", attributes: [
                .font: NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .regular),
                .foregroundColor: theme.color(.textTertiary),
            ]))
        }
        attributedTitle = title
        setAccessibilityLabel(title.string)
        needsDisplay = true
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: attributedTitle.size().width.rounded(.up) + 20, height: 28)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard isOn else { return }
        theme.color(.accent).setFill()
        NSRect(x: 0, y: bounds.maxY - 2, width: bounds.width, height: 2).fill()
    }

    override var isFlipped: Bool { true }
}

/// The draggable divider between the RequestEditor and the ResponseViewer: a 6 pt handle with a
/// 32 × 3 pt grip, and each pane keeping 160 pt (Open UI Q2).
final class EditorSplitView: NSSplitView, NSSplitViewDelegate {
    static let minimumPane: CGFloat = 160
    /// The editor's share of the height: 52 % as on board 02, then wherever the user drags it.
    private(set) var editorFraction: CGFloat = 0.52
    var background = NSColor.clear
    var border = NSColor.separatorColor

    override init(frame: NSRect) {
        super.init(frame: frame)
        isVertical = false
        delegate = self
        setAccessibilityLabel("Resize editor and Response")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var dividerThickness: CGFloat { 6 }

    /// Resizing the window keeps the editor's share; each pane still keeps 160 pt.
    override func resizeSubviews(withOldSize oldSize: NSSize) {
        guard subviews.count == 2 else { return super.resizeSubviews(withOldSize: oldSize) }
        let height = bounds.height - dividerThickness
        let top = min(max((height * editorFraction).rounded(), Self.minimumPane), max(Self.minimumPane, height - Self.minimumPane))
        subviews[0].frame = NSRect(x: 0, y: 0, width: bounds.width, height: top)
        subviews[1].frame = NSRect(x: 0, y: top + dividerThickness, width: bounds.width, height: max(0, height - top))
    }

    /// Only a drag moves the share; NSSplitView tracks the drag inside mouseDown.
    override func mouseDown(with event: NSEvent) {
        super.mouseDown(with: event)
        let height = bounds.height - dividerThickness
        guard height > 0, let editor = subviews.first else { return }
        editorFraction = editor.frame.height / height
    }

    override func drawDivider(in rect: NSRect) {
        background.setFill()
        rect.fill()
        border.setFill()
        NSRect(x: rect.minX, y: rect.minY, width: rect.width, height: 1).fill()
        NSBezierPath(roundedRect: NSRect(x: rect.midX - 16, y: rect.minY + 1, width: 32, height: 3), xRadius: 1.5, yRadius: 1.5).fill()
    }

    func splitView(_ splitView: NSSplitView, constrainMinCoordinate proposedMinimumPosition: CGFloat, ofSubviewAt dividerIndex: Int) -> CGFloat {
        Self.minimumPane
    }

    func splitView(_ splitView: NSSplitView, constrainMaxCoordinate proposedMaximumPosition: CGFloat, ofSubviewAt dividerIndex: Int) -> CGFloat {
        splitView.bounds.height - Self.minimumPane - dividerThickness
    }
}

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

    /// What follows the name: a row count (Disabled Rows too, none for no rows). Auth and Body
    /// show none: the pop-ups in their panes name the scheme and the Body Type.
    func detail(in definition: RequestDefinition) -> String? {
        func count(_ rows: [Row]) -> String? { rows.isEmpty ? nil : "\(rows.count)" }
        return switch self {
        case .params: count(definition.params)
        case .headers: count(definition.headers)
        case .cookies: count(definition.cookies)
        case .body, .auth, .settings: nil
        }
    }

    /// A count holding an Undefined Variable is drawn in `variableUndefined`, so the reason a send
    /// is blocked shows from another section. Disabled Rows are not sent, so they never count. Params
    /// also holds the Path Variable values the URL has; with no count the label takes the colour.
    func holdsUndefined(in definition: RequestDefinition, kinds: VariableKinds) -> Bool {
        let rows: [Row] = switch self {
        case .params: definition.params
        case .headers: definition.headers
        case .cookies: definition.cookies
        case .body, .auth, .settings: []
        }
        let pathValues = self == .params ? PathVariables.sentValues(definition.pathVariables, in: definition.url) : []
        return rows.contains { $0.isEnabled && (kinds.holdsUndefined($0.name) || kinds.holdsUndefined($0.value)) }
            || pathValues.contains(where: kinds.holdsUndefined)
    }

    func title(in definition: RequestDefinition) -> String {
        detail(in: definition).map { "\(name) \($0)" } ?? name
    }
}

/// The section bar over one pane per section (surfaces.md §1 RequestEditor). Params, Headers
/// and Cookies are key/value tables writing the Tab's definition.
final class RequestEditor: NSView {
    private var model: TabModel
    private let theme: ThemeEnvironment
    private(set) var selected = EditorSection.params
    private var buttons: [EditorSection: SectionButton] = [:]
    private var panes: [EditorSection: NSView] = [:]
    private var tables: [EditorSection: KeyValueTable] = [:]
    let paramsPane: ParamsPane
    let settingsPane: SettingsPane
    let authPane: AuthPane
    let bodyPane: BodyPane

    init(model: TabModel, theme: ThemeEnvironment) {
        self.model = model
        self.theme = theme
        settingsPane = SettingsPane(theme: theme)
        paramsPane = ParamsPane(theme: theme)
        authPane = AuthPane(theme: theme)
        bodyPane = BodyPane(model: model, theme: theme)
        super.init(frame: .zero)
        paramsPane.pathTable.onChange = { [weak self] in self?.model.setPathVariable($0, to: $1) }
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
        theme.paint(rule) { $0.fillColor = $1.color(.border) }

        let paneArea = NSView()
        for section in EditorSection.allCases {
            let button = SectionButton(theme: theme, target: self, action: #selector(sectionClicked))
            buttons[section] = button
            bar.addArrangedSubview(button)

            let pane: NSView
            if section == .params {
                let table = paramsPane.queryTable
                table.onChange = { [weak self] in self?.model.tab.definition.params = $0 }
                tables[section] = table
                pane = paramsPane
            } else if let rows = Self.rows(section) {
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
            // Auth pads itself (16 pt) and measures the editor's width, so it takes the whole area.
            let (side, edge): (CGFloat, CGFloat) = section == .auth ? (0, 0) : (12, 8)
            NSLayoutConstraint.activate([
                pane.leadingAnchor.constraint(equalTo: paneArea.leadingAnchor, constant: side),
                pane.trailingAnchor.constraint(equalTo: paneArea.trailingAnchor, constant: -side),
                pane.topAnchor.constraint(equalTo: paneArea.topAnchor, constant: edge),
                pane.bottomAnchor.constraint(lessThanOrEqualTo: paneArea.bottomAnchor, constant: -edge),
            ])
            // A table hugs its rows; any other pane fills the area.
            if !(pane is KeyValueTable) { pane.bottomAnchor.constraint(equalTo: paneArea.bottomAnchor, constant: -edge).isActive = true }
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

    func sectionButton(_ section: EditorSection) -> SectionButton {
        guard let button = buttons[section] else { preconditionFailure("every section has a button") }
        return button
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

    func bind(_ model: TabModel) {
        self.model = model
        bodyPane.bind(model)
        render()
    }

    /// Redraws from the Tab's definition, and again whenever it changes, while it is still the
    /// bound one.
    func render() {
        let bound = model
        withObservationTracking {
            let definition = model.tab.definition
            // Read here, so switching the Active Environment re-runs this render.
            let kinds = model.kinds
            for (section, button) in buttons {
                button.set(name: section.name, detail: section.detail(in: definition), isUndefined: section.holdsUndefined(in: definition, kinds: kinds))
            }
            for (section, table) in tables {
                table.setKinds(kinds)
                if let rows = Self.rows(section) { table.setRows(definition[keyPath: rows]) }
            }
            paramsPane.setPathVariables(names: PathVariables.names(in: definition.url), values: definition.pathVariables, kinds: kinds)
            // An empty Draft or an invalid URL has no host yet, so nothing to show.
            let resolved = try? VariableResolver.resolve(definition, scope: model.scope(.asWritten))
            settingsPane.setSettings(definition.settings)
            authPane.setAuth(definition.auth, headers: definition.headers)
            authPane.setKinds(kinds)
            bodyPane.setBody(definition.body, kinds: kinds)
            table(.headers).setAutomaticRows(resolved.map(AutomaticHeaders.rows) ?? [])
        } onChange: { [weak self] in
            Task { @MainActor in if self?.model === bound { self?.render() } }
        }
    }
}

/// One section in the bar: 28 pt, the name, then its detail in tabular `textTertiary`, and a 2 pt
/// `accent` underline when selected.
final class SectionButton: NSButton {
    private let theme: ThemeEnvironment
    private var name = ""
    private var detail: String?
    private var isUndefined = false
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
        theme.paint(self) { button, _ in button.redraw() }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func set(name: String, detail: String?, isUndefined: Bool = false) {
        guard (name, detail, isUndefined) != (self.name, self.detail, self.isUndefined) else { return }
        (self.name, self.detail, self.isUndefined) = (name, detail, isUndefined)
        redraw()
    }

    /// The label's colour.
    var nameColor: NSColor? { attributedTitle.length > 0 ? attributedTitle.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor : nil }

    /// The count's colour, nil when there is no count.
    var detailColor: NSColor? {
        guard detail != nil, attributedTitle.length > name.utf16.count + 1 else { return nil }
        return attributedTitle.attribute(.foregroundColor, at: name.utf16.count + 1, effectiveRange: nil) as? NSColor
    }

    private func redraw() {
        // With no count to colour, the label itself says an Undefined Variable blocks the send.
        let labelUndefined = isUndefined && detail == nil
        let title = NSMutableAttributedString(string: name, attributes: [
            .font: NSFont.systemFont(ofSize: 13, weight: isOn || labelUndefined ? .semibold : .regular),
            .foregroundColor: theme.color(labelUndefined ? .variableUndefined : isOn ? .text : .textSecondary),
        ])
        if let detail {
            title.append(NSAttributedString(string: " \(detail)", attributes: [
                .font: NSFont.monospacedDigitSystemFont(ofSize: 13, weight: isUndefined ? .semibold : .regular),
                .foregroundColor: theme.color(isUndefined ? .variableUndefined : .textTertiary),
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
final class EditorSplitView: NSSplitView {
    static let minimumPane: CGFloat = 160
    /// The editor's share of the height: 52 %, then wherever the user drags it.
    private(set) var editorFraction: CGFloat = 0.52
    var background = NSColor.clear
    var border = NSColor.separatorColor
    /// Never the split view itself: AppKit's split view passes respondsToSelector: to its
    /// delegate, so being its own delegate recursed until the stack ran out.
    private let limits = PaneLimits()

    override init(frame: NSRect) {
        super.init(frame: frame)
        isVertical = false
        delegate = limits
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
}

/// Each pane of an EditorSplitView keeps 160 pt.
private final class PaneLimits: NSObject, NSSplitViewDelegate {
    func splitView(_ splitView: NSSplitView, constrainMinCoordinate proposedMinimumPosition: CGFloat, ofSubviewAt dividerIndex: Int) -> CGFloat {
        EditorSplitView.minimumPane
    }

    func splitView(_ splitView: NSSplitView, constrainMaxCoordinate proposedMaximumPosition: CGFloat, ofSubviewAt dividerIndex: Int) -> CGFloat {
        splitView.bounds.height - EditorSplitView.minimumPane - splitView.dividerThickness
    }
}

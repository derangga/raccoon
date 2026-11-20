import AppKit
import Observation
import RaccoonData
import RaccoonDomain

/// The Mock Server sheet (design-system §6): native, 460 pt wide, so system colours. It draws what
/// MockSheetModel decides and sends its clicks back. The decisions (state, buttons, the default one)
/// and the text that varies are the model's; only the fixed labels are written here.
/// Nothing in it moves: every state change is one frame.
final class MockServerSheet: NSViewController, NSTextFieldDelegate {
    static let width: CGFloat = 460
    private static let rowHeight: CGFloat = 24
    private static let visibleRows = 6
    /// Two lines of the 11 pt hint: the Port row keeps this height whatever it says.
    private static let noteHeight: CGFloat = 30

    private let model: MockSheetModel
    private let collection: String
    private let theme: ThemeEnvironment

    let portField = NSTextField()
    let corsSwitch = NSSwitch()
    let copyButton = NSButton(title: "Copy URL", target: nil, action: nil)
    let spinner = NSProgressIndicator()
    let statusLabel = NSTextField(wrappingLabelWithString: "")
    let portMessage = NSTextField(wrappingLabelWithString: "")
    let useAnyFreePort = NSButton(title: "use any free port", target: nil, action: nil)
    let routesHeading = NSTextField(labelWithString: "")
    let routesEmpty = NSTextField(labelWithString: "")
    let cancelButton = NSButton(title: "Cancel", target: nil, action: nil)
    let startButton = NSButton(title: "Start Mock Server", target: nil, action: nil)
    let stopButton = NSButton(title: "Stop Mock Server", target: nil, action: nil)
    let restartButton = NSButton(title: "Restart Mock Server", target: nil, action: nil)
    let doneButton = NSButton(title: "Done", target: nil, action: nil)

    private let dot = StatusDot()
    private let routesBox = GroupedBox()
    private let routesScroll = NSScrollView()
    private let routesStack = NSStackView()
    private lazy var routesHeight = routesBox.heightAnchor.constraint(equalToConstant: 0)
    private var shownLines: [MockRouteLine] = []
    private var isOpen = true
    private var spinnerDelay: Task<Void, Never>?

    init(model: MockSheetModel, collection: String, theme: ThemeEnvironment) {
        self.model = model
        self.collection = collection
        self.theme = theme
        super.init(nibName: nil, bundle: nil)
        title = "Mock Server"
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// Shown as a sheet on `parent`; `failure` is a start that just failed, shown as if the sheet
    /// had started it. `theme` colours the method names; without one, the bundled Theme's default
    /// Flavor for the window's appearance.
    static func present(
        on parent: NSWindow, model: WindowModel, collection: String, showing failure: MockError? = nil, theme: ThemeEnvironment? = nil
    ) {
        guard parent.attachedSheet == nil else { return }
        let theme = theme ?? ThemeEnvironment(
            catalog: ThemeCatalog.load(), isDark: parent.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua)
        let sheet = MockServerSheet(
            model: MockSheetModel(window: model, collection: collection, failure: failure, clipboard: SystemClipboardWriter(name: .general)),
            collection: collection, theme: theme)
        let restore = EnvironmentsSheet.rememberFocus(in: parent)
        parent.beginSheet(sheetPanel(sheet, focus: sheet.portField)) { _ in restore() }
    }

    // MARK: Layout

    override func loadView() {
        let root = NSView()
        root.widthAnchor.constraint(equalToConstant: Self.width).isActive = true

        let heading = NSTextField(labelWithString: "Mock Server")
        heading.font = .systemFont(ofSize: 15, weight: .semibold)
        let subtitle = NSTextField(labelWithString: collection)
        subtitle.font = .systemFont(ofSize: 12)
        subtitle.textColor = .secondaryLabelColor
        subtitle.lineBreakMode = .byTruncatingTail

        let header = NSStackView(views: [heading, subtitle])
        header.orientation = .vertical
        header.alignment = .leading
        header.spacing = 2

        let status = statusRow()
        let settings = settingsBox()
        let routes = routesSection()

        let footer = NSTextField(wrappingLabelWithString: "It stops when you quit Raccoon or switch Workspace, and doesn't start again by itself.")
        footer.font = .systemFont(ofSize: 12)
        footer.textColor = .secondaryLabelColor
        footer.preferredMaxLayoutWidth = Self.width - 40

        let buttons = buttonRow()

        let column = NSStackView(views: [header, status, settings, routes, footer, buttons])
        column.orientation = .vertical
        column.alignment = .leading
        column.spacing = 12
        column.setCustomSpacing(14, after: header)
        column.setCustomSpacing(16, after: status)
        column.setCustomSpacing(16, after: settings)
        column.setCustomSpacing(12, after: routes)
        column.setCustomSpacing(16, after: footer)
        column.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(column)
        NSLayoutConstraint.activate([
            column.topAnchor.constraint(equalTo: root.topAnchor, constant: 20),
            column.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 20),
            column.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -20),
            column.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -20),
            subtitle.widthAnchor.constraint(lessThanOrEqualTo: column.widthAnchor),
            status.widthAnchor.constraint(equalTo: column.widthAnchor),
            settings.widthAnchor.constraint(equalTo: column.widthAnchor),
            routes.widthAnchor.constraint(equalTo: column.widthAnchor),
            footer.widthAnchor.constraint(equalTo: column.widthAnchor),
            buttons.widthAnchor.constraint(equalTo: column.widthAnchor),
        ])
        view = root
        render()
    }

    /// The dot, the status text, and at the trailing edge Copy URL, or the spinner while starting.
    private func statusRow() -> NSView {
        statusLabel.preferredMaxLayoutWidth = Self.width - 40 - 14 - 90
        statusLabel.isSelectable = false
        statusLabel.maximumNumberOfLines = 0

        copyButton.isBordered = false
        copyButton.target = self
        copyButton.action = #selector(copyURL)
        copyButton.setAccessibilityLabel("Copy URL")
        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.isIndeterminate = true
        spinner.isDisplayedWhenStopped = false

        let row = NSView()
        for child in [dot, statusLabel, copyButton, spinner] as [NSView] {
            child.translatesAutoresizingMaskIntoConstraints = false
            row.addSubview(child)
        }
        NSLayoutConstraint.activate([
            dot.leadingAnchor.constraint(equalTo: row.leadingAnchor),
            dot.widthAnchor.constraint(equalToConstant: 8),
            dot.heightAnchor.constraint(equalToConstant: 8),
            dot.centerYAnchor.constraint(equalTo: statusLabel.firstBaselineAnchor, constant: -4.5),
            statusLabel.leadingAnchor.constraint(equalTo: dot.trailingAnchor, constant: 8),
            statusLabel.topAnchor.constraint(equalTo: row.topAnchor),
            statusLabel.bottomAnchor.constraint(equalTo: row.bottomAnchor),
            statusLabel.trailingAnchor.constraint(lessThanOrEqualTo: copyButton.leadingAnchor, constant: -8),
            copyButton.trailingAnchor.constraint(equalTo: row.trailingAnchor),
            copyButton.firstBaselineAnchor.constraint(equalTo: statusLabel.firstBaselineAnchor),
            spinner.trailingAnchor.constraint(equalTo: row.trailingAnchor),
            spinner.centerYAnchor.constraint(equalTo: row.topAnchor, constant: 9),
        ])
        return row
    }

    /// Two rows in a grouped box: Port with its hint, and the CORS switch with its hint.
    private func settingsBox() -> NSView {
        let box = GroupedBox()

        let portLabel = NSTextField(labelWithString: "Port")
        portLabel.font = .systemFont(ofSize: 13)
        portField.alignment = .right
        portField.font = .monospacedDigitSystemFont(ofSize: 13, weight: .regular)
        portField.delegate = self
        portField.setAccessibilityLabel("Port")

        portMessage.font = .systemFont(ofSize: 11)
        portMessage.preferredMaxLayoutWidth = Self.width - 40 - 28
        useAnyFreePort.isBordered = false
        useAnyFreePort.target = self
        useAnyFreePort.action = #selector(useAnyFreePortPressed)
        useAnyFreePort.attributedTitle = NSAttributedString(string: "use any free port", attributes: [
            .font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.linkColor, .underlineStyle: NSUnderlineStyle.single.rawValue,
        ])
        useAnyFreePort.setContentHuggingPriority(.required, for: .horizontal)
        useAnyFreePort.setContentCompressionResistancePriority(.required, for: .horizontal)
        let note = NSStackView(views: [portMessage, useAnyFreePort])
        note.spacing = 3
        note.alignment = .firstBaseline
        let noteArea = NSView()
        note.translatesAutoresizingMaskIntoConstraints = false
        noteArea.addSubview(note)

        let rule = NSBox()
        rule.boxType = .separator

        let corsLabel = NSTextField(labelWithString: "Allow browser requests (CORS)")
        corsLabel.font = .systemFont(ofSize: 13)
        let corsHint = NSTextField(labelWithString: "Lets web pages on other sites call this server.")
        corsHint.font = .systemFont(ofSize: 11)
        corsHint.textColor = .secondaryLabelColor
        corsSwitch.target = self
        corsSwitch.action = #selector(corsToggled)
        corsSwitch.setAccessibilityLabel("Allow browser requests (CORS)")

        for child in [portLabel, portField, noteArea, rule, corsLabel, corsHint, corsSwitch] as [NSView] {
            child.translatesAutoresizingMaskIntoConstraints = false
            box.addSubview(child)
        }
        NSLayoutConstraint.activate([
            portField.topAnchor.constraint(equalTo: box.topAnchor, constant: 10),
            portField.trailingAnchor.constraint(equalTo: box.trailingAnchor, constant: -14),
            portField.widthAnchor.constraint(equalToConstant: 90),
            portLabel.leadingAnchor.constraint(equalTo: box.leadingAnchor, constant: 14),
            portLabel.firstBaselineAnchor.constraint(equalTo: portField.firstBaselineAnchor),
            noteArea.topAnchor.constraint(equalTo: portField.bottomAnchor, constant: 4),
            noteArea.leadingAnchor.constraint(equalTo: box.leadingAnchor, constant: 14),
            noteArea.trailingAnchor.constraint(equalTo: box.trailingAnchor, constant: -14),
            noteArea.heightAnchor.constraint(equalToConstant: Self.noteHeight),
            note.topAnchor.constraint(equalTo: noteArea.topAnchor),
            note.leadingAnchor.constraint(equalTo: noteArea.leadingAnchor),
            note.trailingAnchor.constraint(lessThanOrEqualTo: noteArea.trailingAnchor),
            rule.topAnchor.constraint(equalTo: noteArea.bottomAnchor, constant: 6),
            rule.leadingAnchor.constraint(equalTo: box.leadingAnchor, constant: 14),
            rule.trailingAnchor.constraint(equalTo: box.trailingAnchor),
            corsLabel.topAnchor.constraint(equalTo: rule.bottomAnchor, constant: 12),
            corsLabel.leadingAnchor.constraint(equalTo: box.leadingAnchor, constant: 14),
            corsSwitch.centerYAnchor.constraint(equalTo: corsLabel.bottomAnchor, constant: 1),
            corsSwitch.trailingAnchor.constraint(equalTo: box.trailingAnchor, constant: -14),
            corsLabel.trailingAnchor.constraint(lessThanOrEqualTo: corsSwitch.leadingAnchor, constant: -8),
            corsHint.topAnchor.constraint(equalTo: corsLabel.bottomAnchor, constant: 2),
            corsHint.leadingAnchor.constraint(equalTo: corsLabel.leadingAnchor),
            corsHint.bottomAnchor.constraint(equalTo: box.bottomAnchor, constant: -12),
        ])
        return box
    }

    /// The heading, then a grouped box that shows six rows and scrolls past that.
    private func routesSection() -> NSView {
        routesHeading.font = .systemFont(ofSize: 12, weight: .semibold)
        routesHeading.textColor = .secondaryLabelColor

        routesStack.orientation = .vertical
        routesStack.alignment = .leading
        routesStack.spacing = 0
        routesStack.translatesAutoresizingMaskIntoConstraints = false
        routesScroll.documentView = routesStack
        routesScroll.hasVerticalScroller = true
        routesScroll.autohidesScrollers = true
        routesScroll.drawsBackground = false
        routesScroll.setAccessibilityLabel("Routes")

        routesEmpty.font = .systemFont(ofSize: 12)
        routesEmpty.textColor = .secondaryLabelColor
        routesEmpty.alignment = .center
        routesEmpty.lineBreakMode = .byTruncatingTail

        for child in [routesScroll, routesEmpty] as [NSView] {
            child.translatesAutoresizingMaskIntoConstraints = false
            routesBox.addSubview(child)
        }
        let section = NSStackView(views: [routesHeading, routesBox])
        section.orientation = .vertical
        section.alignment = .leading
        section.spacing = 6
        let clip = routesScroll.contentView
        NSLayoutConstraint.activate([
            routesHeight,
            routesBox.widthAnchor.constraint(equalTo: section.widthAnchor),
            routesScroll.topAnchor.constraint(equalTo: routesBox.topAnchor, constant: 1),
            routesScroll.bottomAnchor.constraint(equalTo: routesBox.bottomAnchor, constant: -1),
            routesScroll.leadingAnchor.constraint(equalTo: routesBox.leadingAnchor, constant: 1),
            routesScroll.trailingAnchor.constraint(equalTo: routesBox.trailingAnchor, constant: -1),
            routesStack.topAnchor.constraint(equalTo: clip.topAnchor),
            routesStack.leadingAnchor.constraint(equalTo: clip.leadingAnchor),
            routesStack.widthAnchor.constraint(equalTo: clip.widthAnchor),
            routesEmpty.centerYAnchor.constraint(equalTo: routesBox.centerYAnchor),
            routesEmpty.leadingAnchor.constraint(equalTo: routesBox.leadingAnchor, constant: 14),
            routesEmpty.trailingAnchor.constraint(equalTo: routesBox.trailingAnchor, constant: -14),
        ])
        return section
    }

    /// Stop Mock Server at the leading edge; the others trailing, the default one filled.
    private func buttonRow() -> NSView {
        let pairs: [(NSButton, Selector)] = [
            (cancelButton, #selector(closeSheet)), (startButton, #selector(startPressed)), (stopButton, #selector(stopPressed)),
            (restartButton, #selector(restartPressed)), (doneButton, #selector(closeSheet)),
        ]
        for (button, action) in pairs {
            button.target = self
            button.action = action
        }
        let spacer = NSView()
        spacer.setContentHuggingPriority(.init(1), for: .horizontal)
        let row = NSStackView(views: [stopButton, spacer, cancelButton, restartButton, startButton, doneButton])
        row.spacing = 8
        row.setCustomSpacing(0, after: stopButton)
        return row
    }

    // MARK: Drawing the model

    private func button(for action: MockSheetAction) -> NSButton {
        switch action {
        case .cancel: cancelButton
        case .start: startButton
        case .stop: stopButton
        case .restart: restartButton
        case .done: doneButton
        }
    }

    /// Re-runs whenever anything the model reads changes, until the sheet closes: its own state,
    /// the window's running servers, the Collection's files and the Theme.
    private func render() {
        guard isOpen else { return }
        withObservationTracking {
            // Its Collection renamed, trashed or its Workspace left: nothing here to configure.
            if model.isCollectionGone { return closeSheet() }
            draw()
        } onChange: { [weak self] in
            Task { @MainActor in self?.render() }
        }
    }

    private func draw() {
        let state = model.state

        dot.color = if case .running = state { .systemGreen } else { .tertiaryLabelColor }
        statusLabel.attributedStringValue = statusText(state)
        statusLabel.setAccessibilityLabel(model.statusText)
        let isRunning = model.statusURL != nil
        copyButton.isHidden = !isRunning
        copyButton.attributedTitle = NSAttributedString(
            string: model.copied ? "Copied" : "Copy URL", attributes: [.font: NSFont.systemFont(ofSize: 12), .foregroundColor: NSColor.secondaryLabelColor])
        showSpinner(state == .starting)

        if portField.stringValue != model.portText { portField.stringValue = model.portText }
        portMessage.stringValue = model.portMessage
        portMessage.textColor = model.portMessageIsError ? .systemRed : .secondaryLabelColor
        useAnyFreePort.isHidden = !model.showsUseAnyFreePort
        corsSwitch.state = model.allowsCORS ? .on : .off

        drawRoutes()

        for action in [MockSheetAction.cancel, .start, .stop, .restart, .done] {
            let control = button(for: action)
            control.isHidden = !model.actions.contains(action)
            control.isEnabled = model.isEnabled(action)
            control.keyEquivalent = model.defaultAction == action ? "\r" : action == .cancel ? "\u{1b}" : ""
        }
        fitSheet()
    }

    private func statusText(_ state: MockSheetState) -> NSAttributedString {
        let plain: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 13), .foregroundColor: NSColor.labelColor]
        if let url = model.statusURL {
            let text = NSMutableAttributedString(string: "Running at ", attributes: plain)
            text.append(NSAttributedString(string: url, attributes: [.font: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular), .foregroundColor: NSColor.labelColor]))
            return text
        }
        if model.statusIsError {
            return NSAttributedString(string: model.statusText, attributes: [.font: NSFont.systemFont(ofSize: 12), .foregroundColor: NSColor.systemRed])
        }
        return NSAttributedString(string: model.statusText, attributes: plain)
    }

    /// The system spinner, 150 ms after a start began; a start that is quicker never shows it.
    private func showSpinner(_ starting: Bool) {
        if starting {
            guard spinnerDelay == nil else { return }
            spinnerDelay = Task { [spinner] in
                try? await Task.sleep(for: .milliseconds(150))
                if !Task.isCancelled { spinner.startAnimation(nil) }
            }
        } else {
            spinnerDelay?.cancel()
            spinnerDelay = nil
            spinner.stopAnimation(nil)
        }
    }

    /// Rebuilds the rows only when they changed, so typing in the Port field never resets the scroll.
    private func drawRoutes() {
        let lines = model.routeLines
        routesHeading.stringValue = model.routesHeading
        routesHeading.isHidden = lines.isEmpty
        routesEmpty.stringValue = model.routesEmptyText ?? ""
        routesEmpty.isHidden = !lines.isEmpty
        routesScroll.isHidden = lines.isEmpty
        routesHeight.constant = lines.isEmpty ? 40 : CGFloat(min(lines.count, Self.visibleRows)) * Self.rowHeight + 2
        guard lines != shownLines else { return }
        shownLines = lines
        routesStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        for line in lines {
            let row = RouteRow(line, color: theme.color(.method(line.method)))
            routesStack.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: routesStack.widthAnchor).isActive = true
        }
    }

    /// The sheet is as tall as its content, anchored at its top edge; no animation.
    private func fitSheet() {
        guard let panel = view.window else { return }
        view.layoutSubtreeIfNeeded()
        let height = panel.frameRect(forContentRect: NSRect(origin: .zero, size: view.fittingSize)).height
        var frame = panel.frame
        guard abs(frame.height - height) > 0.5 else { return }
        frame.origin.y += frame.height - height
        frame.size.height = height
        panel.setFrame(frame, display: true, animate: false)
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        fitSheet()
    }

    // MARK: Clicks

    func controlTextDidChange(_ notification: Notification) {
        model.editPort(portField.stringValue)
    }

    @objc private func corsToggled() { model.setAllowsCORS(corsSwitch.state == .on) }
    @objc private func copyURL() { model.copyURL() }
    @objc private func startPressed() { Task { await model.start() } }
    @objc private func restartPressed() { Task { await model.restart() } }
    @objc private func useAnyFreePortPressed() { Task { await model.useAnyFreePort() } }
    @objc private func stopPressed() { model.stop() }

    /// Cancel and Done. Closing never stops a running server.
    @objc private func closeSheet() {
        isOpen = false
        spinnerDelay?.cancel()
        model.close()
        if let panel = view.window, let parent = panel.sheetParent { parent.endSheet(panel) }
    }

    /// Esc.
    override func cancelOperation(_ sender: Any?) {
        guard model.isEnabled(.cancel) else { return }
        closeSheet()
    }
}

/// A route: the method in its colour, the path in SF Mono, the Example count trailing.
private final class RouteRow: NSView {
    init(_ line: MockRouteLine, color: NSColor) {
        super.init(frame: .zero)
        let method = NSTextField(labelWithString: "")
        method.attributedStringValue = NSAttributedString(string: line.method, attributes: [
            .font: NSFont.monospacedSystemFont(ofSize: 9.5, weight: .bold), .foregroundColor: color, .kern: 0.19,
        ])
        let path = NSTextField(labelWithString: line.path)
        path.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        path.lineBreakMode = .byTruncatingMiddle
        path.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let detail = NSTextField(labelWithString: line.detail)
        detail.font = .systemFont(ofSize: 12)
        detail.textColor = line.isServed ? .secondaryLabelColor : .tertiaryLabelColor
        detail.setContentCompressionResistancePriority(.required, for: .horizontal)
        for child in [method, path, detail] as [NSView] {
            child.translatesAutoresizingMaskIntoConstraints = false
            addSubview(child)
        }
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 24),
            method.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            method.widthAnchor.constraint(equalToConstant: 52),
            method.centerYAnchor.constraint(equalTo: centerYAnchor),
            path.leadingAnchor.constraint(equalTo: method.trailingAnchor, constant: 4),
            path.centerYAnchor.constraint(equalTo: centerYAnchor),
            detail.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            detail.centerYAnchor.constraint(equalTo: centerYAnchor),
            path.trailingAnchor.constraint(lessThanOrEqualTo: detail.leadingAnchor, constant: -8),
        ])
        setAccessibilityElement(true)
        setAccessibilityLabel("\(line.method) \(line.path), \(line.detail)")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }
}

/// The Workspaces sheet's grouped box: an 8 pt radius, a 1 pt `separatorColor` border and the
/// control background. Drawn, so its colours resolve in the sheet's appearance.
private final class GroupedBox: NSView {
    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 8, yRadius: 8)
        NSColor.controlBackgroundColor.setFill()
        path.fill()
        NSColor.separatorColor.setStroke()
        path.lineWidth = 1
        path.stroke()
    }
}

/// The 8 pt status dot: `systemGreen` while running, tertiary otherwise.
private final class StatusDot: NSView {
    var color = NSColor.tertiaryLabelColor { didSet { needsDisplay = true } }

    override func draw(_ dirtyRect: NSRect) {
        color.setFill()
        NSBezierPath(ovalIn: bounds).fill()
    }
}

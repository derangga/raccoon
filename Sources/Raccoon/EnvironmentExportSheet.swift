import AppKit
import RaccoonDomain

/// What the Environment Export sheet says (design-system §6): every string, from the Environment.
/// Pure, so a test reads them without a window.
struct EnvironmentExportModel: Equatable {
    let environment: Environment

    init(_ environment: Environment) { self.environment = environment }

    var title: String { "Export “\(environment.name)”" }

    /// The save panel's name for the file.
    var fileName: String { RequestFileName.sanitised(environment.name) + ".postman_environment.json" }

    var counts: String {
        let secrets = environment.entries.filter { $0.value == .secret }.count
        return "\(PostmanImport.plural(environment.entries.count, "Variable")), \(PostmanImport.plural(secrets, "secret"))"
    }

    /// With no secret the checkbox and its hint are not drawn.
    var hasSecrets: Bool { environment.entries.contains { $0.value == .secret } }

    func hint(ticked: Bool) -> String {
        ticked ? "Secret values are written to the file in plain text." : "Secrets are exported empty."
    }

    func exported(_ fileName: String) -> String { "Exported to \(fileName)" }

    func unreadable(_ count: Int) -> String {
        "\(PostmanImport.number(count)) \(count == 1 ? "secret could not be read from the Keychain and is" : "secrets could not be read from the Keychain and are") empty in the file."
    }

    /// The red line above the buttons.
    func failure(_ error: StoreError) -> String {
        "Not exported. \(EnvironmentsSheet.sentence(error.reason))"
    }
}

/// The Environment Export sheet (design-system §6): native, 380 pt wide, so system colours. Export…
/// asks for a place, then (box ticked) reads the Secret Variables from the Keychain, never before,
/// then writes the file.
final class EnvironmentExportSheet: NSViewController {
    static let width: CGFloat = 380
    /// The body's width inside the 20 pt margins.
    static let bodyWidth = width - 40
    private static let namesFont = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)

    let titleLabel = NSTextField(labelWithString: "")
    let countsLabel = NSTextField(labelWithString: "")
    let includeBox = NSButton(checkboxWithTitle: "Include secret values", target: nil, action: nil)
    let hintLabel = NSTextField(labelWithString: "")
    let failureLabel = NSTextField(labelWithString: "")
    let cancelButton = NSButton(title: "Cancel", target: nil, action: nil)
    let exportButton = NSButton(title: "Export…", target: nil, action: nil)
    let doneButton = NSButton(title: "Done", target: nil, action: nil)
    /// The result, only when a secret could not be read: it replaces the form.
    let resultStack = NSStackView()
    let resultLabel = NSTextField(labelWithString: "")
    let unreadableLabel = NSTextField(wrappingLabelWithString: "")
    let namesLabel = NSTextField(labelWithString: "")

    private let model: EnvironmentExportModel
    /// Called after the save panel has returned, with the box ticked, and never otherwise.
    private let readSecrets: () -> EnvironmentSecrets
    private let writer: any FileWriting
    /// The save panel as a sheet on this one, with the name to offer; nil on Cancel.
    private let choose: (NSWindow, String) async -> URL?
    private let id: () -> UUID
    private let now: () -> Date
    private let version: String
    /// Runs after the file is written with nothing to report.
    var onExported: () -> Void = {}

    init(
        model: EnvironmentExportModel, readSecrets: @escaping () -> EnvironmentSecrets, writer: any FileWriting,
        choose: @escaping (NSWindow, String) async -> URL?, id: @escaping () -> UUID, now: @escaping () -> Date, version: String
    ) {
        self.model = model
        self.readSecrets = readSecrets
        self.writer = writer
        self.choose = choose
        self.id = id
        self.now = now
        self.version = version
        super.init(nibName: nil, bundle: nil)
        title = model.title
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// A sheet on the Environments sheet's own panel; focus goes back to where it was there when
    /// this one ends, either way (surfaces.md §8).
    static func present(
        on parent: NSWindow, environment: Environment, readSecrets: @escaping () -> EnvironmentSecrets, writer: any FileWriting,
        id: @escaping () -> UUID, now: @escaping () -> Date, version: String
    ) {
        let restore = EnvironmentsSheet.rememberFocus(in: parent)
        let sheet = EnvironmentExportSheet(
            model: EnvironmentExportModel(environment), readSecrets: readSecrets, writer: writer,
            choose: CollectionExportSheet.savePanel, id: id, now: now, version: version
        )
        sheet.onExported = { [weak sheet] in sheet?.endSheet(.OK) }
        parent.beginSheet(sheetPanel(sheet, focus: sheet.exportButton)) { _ in restore() }
    }

    // MARK: Layout

    override func loadView() {
        titleLabel.stringValue = model.title
        titleLabel.font = .systemFont(ofSize: 15, weight: .semibold)
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        countsLabel.stringValue = model.counts
        countsLabel.font = .systemFont(ofSize: 12)
        countsLabel.textColor = .secondaryLabelColor

        includeBox.font = .systemFont(ofSize: 13)
        includeBox.state = .off
        includeBox.target = self
        includeBox.action = #selector(includeChanged)
        includeBox.isHidden = !model.hasSecrets
        hintLabel.font = .systemFont(ofSize: 11)
        hintLabel.textColor = .secondaryLabelColor
        hintLabel.stringValue = model.hint(ticked: false)
        hintLabel.isHidden = !model.hasSecrets

        failureLabel.font = .systemFont(ofSize: 11)
        failureLabel.textColor = .systemRed
        failureLabel.lineBreakMode = .byTruncatingTail
        failureLabel.isHidden = true

        cancelButton.keyEquivalent = "\u{1b}"
        cancelButton.target = self
        cancelButton.action = #selector(close)
        exportButton.keyEquivalent = "\r"
        exportButton.target = self
        exportButton.action = #selector(exportPressed)
        doneButton.keyEquivalent = "\r"
        doneButton.target = self
        doneButton.action = #selector(close)
        doneButton.isHidden = true
        let buttons = NSStackView(views: [cancelButton, exportButton, doneButton])
        buttons.spacing = 8

        let check = NSImageView(image: NSImage(systemSymbolName: "checkmark", accessibilityDescription: nil)!)
        check.symbolConfiguration = .init(pointSize: 12, weight: .regular)
        check.contentTintColor = .systemGreen
        resultLabel.font = .systemFont(ofSize: 13)
        resultLabel.lineBreakMode = .byTruncatingMiddle
        resultLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let written = NSStackView(views: [check, resultLabel])
        written.spacing = 8
        let triangle = NSImageView(image: NSImage(systemSymbolName: "exclamationmark.triangle.fill", accessibilityDescription: nil)!)
        triangle.symbolConfiguration = .init(pointSize: 14, weight: .regular)
        triangle.contentTintColor = .systemOrange
        unreadableLabel.font = .systemFont(ofSize: 12)
        unreadableLabel.preferredMaxLayoutWidth = Self.bodyWidth - 22
        namesLabel.font = Self.namesFont
        namesLabel.textColor = .secondaryLabelColor
        // One line: a single name too long is cut in the middle, so "and N more" stays readable.
        namesLabel.lineBreakMode = .byTruncatingMiddle
        namesLabel.maximumNumberOfLines = 1
        namesLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let detail = NSStackView(views: [unreadableLabel, namesLabel])
        detail.orientation = .vertical
        detail.alignment = .leading
        detail.spacing = 2
        let warning = NSStackView(views: [triangle, detail])
        warning.alignment = .top
        warning.spacing = 6
        resultStack.setViews([written, warning], in: .top)
        resultStack.orientation = .vertical
        resultStack.alignment = .leading
        resultStack.spacing = 8
        resultStack.isHidden = true

        let column = NSStackView(views: [titleLabel, countsLabel, includeBox, hintLabel, resultStack, failureLabel, buttons])
        column.orientation = .vertical
        column.alignment = .leading
        column.spacing = 6
        column.setCustomSpacing(14, after: countsLabel)
        column.setCustomSpacing(0, after: includeBox)
        column.setCustomSpacing(16, after: hintLabel)
        column.setCustomSpacing(16, after: resultStack)
        column.setCustomSpacing(16, after: failureLabel)
        column.translatesAutoresizingMaskIntoConstraints = false

        let view = NSView()
        view.addSubview(column)
        NSLayoutConstraint.activate([
            view.widthAnchor.constraint(equalToConstant: Self.width),
            column.topAnchor.constraint(equalTo: view.topAnchor, constant: 20),
            column.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            column.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            column.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -20),
            titleLabel.widthAnchor.constraint(lessThanOrEqualTo: column.widthAnchor),
            countsLabel.widthAnchor.constraint(lessThanOrEqualTo: column.widthAnchor),
            hintLabel.leadingAnchor.constraint(equalTo: includeBox.leadingAnchor, constant: 19),
            resultStack.widthAnchor.constraint(equalTo: column.widthAnchor),
            failureLabel.widthAnchor.constraint(lessThanOrEqualTo: column.widthAnchor),
            buttons.widthAnchor.constraint(equalTo: column.widthAnchor),
        ])
        buttons.setHuggingPriority(.defaultLow, for: .horizontal)
        cancelButton.setContentHuggingPriority(.required, for: .horizontal)
        buttons.alignment = .centerY
        buttons.distribution = .gravityAreas
        buttons.setViews([cancelButton, exportButton, doneButton], in: .trailing)
        self.view = view
    }

    @objc private func includeChanged() {
        hintLabel.stringValue = model.hint(ticked: includeBox.state == .on)
    }

    // MARK: Cancel, Export…, Done

    @objc private func close() {
        endSheet(.cancel)
    }

    /// Esc, whichever of Cancel and Done is showing.
    override func cancelOperation(_ sender: Any?) { close() }

    @objc private func exportPressed() {
        // At once: a second press before the task has run would ask for a second save panel.
        exportButton.isEnabled = false
        Task { await export() }
    }

    /// The save panel as a sheet on this one; then, ticked, the Keychain; then the file. Cancel in
    /// the panel changes nothing and reads nothing. A failed write stays here as a red line, the
    /// values read dropped with it, and is never retried. A secret the Keychain refused is a name
    /// in the result, never a failed export.
    func export() async {
        guard let sheetWindow = view.window else { return }
        exportButton.isEnabled = false
        // Back on the form: re-enabled on the two paths that stay on it. A result or a close leaves it off.
        guard let url = await choose(sheetWindow, model.fileName) else { return exportButton.isEnabled = true }
        let secrets = includeBox.state == .on ? readSecrets() : .none
        let data = PostmanExporter.environment(model.environment, secrets: secrets, id: id(), exportedAt: now(), version: version)
        do throws(StoreError) {
            try writer.write(data, to: url)
        } catch {
            failureLabel.stringValue = model.failure(error)
            failureLabel.toolTip = failureLabel.stringValue
            failureLabel.isHidden = false
            return exportButton.isEnabled = true
        }
        failureLabel.isHidden = true
        if secrets.unreadable.isEmpty { onExported() } else { showResult(file: url.lastPathComponent, unreadable: secrets.unreadable) }
    }

    /// The form is replaced by where the file went and which secrets are empty in it.
    private func showResult(file: String, unreadable: [VariableName]) {
        let names = unreadable.map(\.rawValue)
        resultLabel.stringValue = model.exported(file)
        resultLabel.toolTip = file
        unreadableLabel.stringValue = model.unreadable(names.count)
        namesLabel.stringValue = PostmanImport.namesLine(names, width: Self.bodyWidth - 22) { text in
            NSAttributedString(string: text, attributes: [.font: Self.namesFont]).size().width
        }
        namesLabel.toolTip = names.joined(separator: " · ")
        for hidden in [titleLabel, countsLabel, includeBox, hintLabel, failureLabel, cancelButton, exportButton] as [NSView] { hidden.isHidden = true }
        resultStack.isHidden = false
        doneButton.isHidden = false
        view.window?.defaultButtonCell = doneButton.cell as? NSButtonCell
    }

    private func endSheet(_ response: NSApplication.ModalResponse) {
        if let panel = view.window, let parent = panel.sheetParent { parent.endSheet(panel, returnCode: response) }
    }
}

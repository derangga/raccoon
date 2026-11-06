import AppKit
import RaccoonDomain

/// What the Collection Export sheet says (design-system §6): every string, from a finished step
/// or the plan. Pure, so a test reads them without a window.
struct CollectionExportModel: Equatable {
    /// One block under the counts: a warning or an info line, and the names it applies to.
    struct Notice: Equatable {
        enum Kind { case credentials, skipped, dirty }

        var kind: Kind
        var headline: String
        var detail: String?
        var names: [String]
        /// What hovering the names line shows; nil: the names, whole.
        var tooltip: String? = nil
    }

    let name: String
    /// The Data Folder, abbreviated with `~`.
    let folder: String

    var title: String { "Export “\(name)”" }

    /// The save panel's name for the file.
    var fileName: String { RequestFileName.sanitised(name) + ".postman_collection.json" }

    func text(of step: ExportStep) -> String {
        switch step {
        case .read(let count): "Read \(PostmanImport.plural(count, "Request")) from \(folder)"
        case .formatted: "Formatted as Collection Format v2.1"
        case .scanned: "Scanned for credentials"
        }
    }

    func counts(_ plan: ExportPlan) -> String {
        "\(PostmanImport.plural(plan.requests, "Request")) · \(PostmanImport.plural(plan.folders, "Folder"))"
    }

    /// Credentials, then the files left out, then the Dirty Requests; each only when there is one.
    func notices(_ plan: ExportPlan) -> [Notice] {
        var notices: [Notice] = []
        if !plan.findings.isEmpty {
            let n = plan.findings.count
            notices.append(Notice(
                kind: .credentials, headline: "\(PostmanImport.number(n)) credential\(n == 1 ? "" : "s") in plain text",
                detail: "The file keeps them exactly as typed.", names: plan.findings.map(\.request).droppingRepeats()
            ))
        }
        if !plan.skipped.isEmpty {
            let n = plan.skipped.count
            notices.append(Notice(
                kind: .skipped, headline: "\(PostmanImport.number(n)) file\(n == 1 ? " is" : "s are") not exported",
                detail: "Raccoon can't read it as a Request, and won't change it.",
                names: plan.skipped.map(\.fileName),
                tooltip: plan.skipped.map { "\($0.fileName): \($0.reason)" }.joined(separator: "\n")
            ))
        }
        if !plan.dirtyRequests.isEmpty {
            let n = plan.dirtyRequests.count
            notices.append(Notice(
                kind: .dirty,
                headline: n == 1 ? "1 Request has edits in a Tab. Export uses what is saved."
                    : "\(PostmanImport.number(n)) Requests have edits in Tabs. Export uses what is saved.",
                detail: nil, names: []
            ))
        }
        return notices
    }

    /// The red line above the buttons.
    func failure(_ error: StoreError) -> String {
        "Not exported. \(EnvironmentsSheet.sentence(error.reason))"
    }
}

/// The Collection Export sheet (design-system §6): native, 440 pt wide, so system colours. It
/// draws the steps as they arrive, then the counts and warnings, and Export… saves the plan's
/// bytes where the save panel says.
final class CollectionExportSheet: NSViewController {
    static let width: CGFloat = 440
    /// The body's width inside the 20 pt margins.
    static let bodyWidth = width - 40
    private static let namesFont = NSFont.systemFont(ofSize: 11)

    /// One checked step: a 12 pt green check and the text. Alpha 0 until its step has finished,
    /// so the sheet's height is the same from the first frame.
    final class StepRow: NSView {
        let label = NSTextField(labelWithString: "")
        private let check = NSImageView(image: NSImage(systemSymbolName: "checkmark", accessibilityDescription: nil)!)

        init() {
            super.init(frame: .zero)
            check.symbolConfiguration = .init(pointSize: 12, weight: .regular)
            check.contentTintColor = .systemGreen
            label.font = .systemFont(ofSize: 13)
            label.textColor = .labelColor
            label.lineBreakMode = .byTruncatingMiddle
            label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            alphaValue = 0
            for child in [check, label] as [NSView] {
                child.translatesAutoresizingMaskIntoConstraints = false
                addSubview(child)
            }
            NSLayoutConstraint.activate([
                heightAnchor.constraint(equalToConstant: 22),
                check.leadingAnchor.constraint(equalTo: leadingAnchor),
                check.widthAnchor.constraint(equalToConstant: 12),
                check.centerYAnchor.constraint(equalTo: centerYAnchor),
                label.leadingAnchor.constraint(equalTo: check.trailingAnchor, constant: 8),
                label.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor),
                label.centerYAnchor.constraint(equalTo: centerYAnchor),
            ])
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }
    }

    /// A warning or info block under the counts.
    final class NoticeView: NSView {
        let headline = NSTextField(wrappingLabelWithString: "")
        let names = NSTextField(labelWithString: "")

        init(_ notice: CollectionExportModel.Notice, names fitted: String) {
            super.init(frame: .zero)
            let isInfo = notice.kind == .dirty
            let image = NSImageView(image: NSImage(systemSymbolName: isInfo ? "info.circle" : "exclamationmark.triangle.fill", accessibilityDescription: nil)!)
            image.symbolConfiguration = .init(pointSize: 14, weight: .regular)
            image.contentTintColor = isInfo ? .secondaryLabelColor : .systemOrange
            headline.stringValue = notice.headline
            headline.font = isInfo ? .systemFont(ofSize: 12) : .systemFont(ofSize: 13, weight: .semibold)
            headline.textColor = isInfo ? .secondaryLabelColor : .labelColor
            headline.preferredMaxLayoutWidth = CollectionExportSheet.bodyWidth - 22
            let column = NSStackView(views: [headline])
            column.orientation = .vertical
            column.alignment = .leading
            column.spacing = 2
            if let detail = notice.detail {
                let line = NSTextField(wrappingLabelWithString: detail)
                line.font = .systemFont(ofSize: 12)
                line.textColor = .secondaryLabelColor
                line.preferredMaxLayoutWidth = CollectionExportSheet.bodyWidth - 22
                column.addArrangedSubview(line)
            }
            if !fitted.isEmpty {
                names.stringValue = fitted
                names.font = CollectionExportSheet.namesFont
                names.textColor = .secondaryLabelColor
                // One line: a single name too long is cut in the middle, so "and N more" stays readable.
                names.lineBreakMode = .byTruncatingMiddle
                names.maximumNumberOfLines = 1
                names.toolTip = notice.tooltip ?? notice.names.joined(separator: " · ")
                names.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
                column.addArrangedSubview(names)
            }
            for child in [image, column] as [NSView] {
                child.translatesAutoresizingMaskIntoConstraints = false
                addSubview(child)
            }
            NSLayoutConstraint.activate([
                widthAnchor.constraint(equalToConstant: CollectionExportSheet.bodyWidth),
                image.leadingAnchor.constraint(equalTo: leadingAnchor),
                image.topAnchor.constraint(equalTo: topAnchor),
                image.widthAnchor.constraint(equalToConstant: 16),
                column.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 22),
                column.trailingAnchor.constraint(equalTo: trailingAnchor),
                column.topAnchor.constraint(equalTo: topAnchor),
                column.bottomAnchor.constraint(equalTo: bottomAnchor),
            ])
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }
    }

    let titleLabel = NSTextField(labelWithString: "")
    let stepRows = (0..<3).map { _ in StepRow() }
    /// Over the first row's check until the first step has finished and the read took over 150 ms.
    let spinner = NSProgressIndicator()
    let details = NSStackView()
    let countsLabel = NSTextField(labelWithString: "")
    private(set) var noticeViews: [NoticeView] = []
    let failureLabel = NSTextField(labelWithString: "")
    let cancelButton = NSButton(title: "Cancel", target: nil, action: nil)
    let exportButton = NSButton(title: "Export…", target: nil, action: nil)

    private let model: CollectionExportModel
    private let steps: AsyncStream<ExportStep>
    private let writer: any FileWriting
    /// The save panel as a sheet on this one, with the name to offer; nil on Cancel.
    private let choose: (NSWindow, String) async -> URL?
    private let reduceMotion: () -> Bool
    /// Runs after the file is written.
    var onExported: () -> Void = {}
    private var plan: ExportPlan?
    private var running: Task<Void, Never>?
    private var reveals: [Task<Void, Never>] = []
    private var spinnerDelay: Task<Void, Never>?

    init(
        model: CollectionExportModel, steps: AsyncStream<ExportStep>, writer: any FileWriting,
        choose: @escaping (NSWindow, String) async -> URL?, reduceMotion: @escaping () -> Bool
    ) {
        self.model = model
        self.steps = steps
        self.writer = writer
        self.choose = choose
        self.reduceMotion = reduceMotion
        super.init(nibName: nil, bundle: nil)
        title = model.title
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// Focus goes back to where it was when the sheet ends, either way (surfaces.md §8).
    static func present(
        on parent: NSWindow, model: CollectionExportModel, steps: AsyncStream<ExportStep>, writer: any FileWriting,
        reduceMotion: @escaping () -> Bool
    ) {
        let restore = EnvironmentsSheet.rememberFocus(in: parent)
        let sheet = CollectionExportSheet(model: model, steps: steps, writer: writer, choose: savePanel, reduceMotion: reduceMotion)
        sheet.onExported = { [weak sheet] in sheet?.endSheet(.OK) }
        parent.beginSheet(sheetPanel(sheet, focus: sheet.exportButton)) { _ in
            sheet.stop()
            restore()
        }
    }

    /// `.json`, with the name the caller offers, in the folder the panel last used. Both Export sheets use it.
    static func savePanel(on sheet: NSWindow, name: String) async -> URL? {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = name
        return await panel.beginSheetModal(for: sheet) == .OK ? panel.url : nil
    }

    // MARK: Layout

    override func loadView() {
        titleLabel.stringValue = model.title
        titleLabel.font = .systemFont(ofSize: 15, weight: .semibold)
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let stepsStack = NSStackView(views: stepRows)
        stepsStack.orientation = .vertical
        stepsStack.alignment = .leading
        stepsStack.spacing = 0
        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.isIndeterminate = true
        spinner.isDisplayedWhenStopped = false
        spinner.translatesAutoresizingMaskIntoConstraints = false
        stepsStack.addSubview(spinner)

        countsLabel.font = .systemFont(ofSize: 13)
        details.orientation = .vertical
        details.alignment = .leading
        details.spacing = 8
        details.addArrangedSubview(countsLabel)
        details.isHidden = true

        failureLabel.font = .systemFont(ofSize: 11)
        failureLabel.textColor = .systemRed
        failureLabel.lineBreakMode = .byTruncatingTail
        failureLabel.isHidden = true

        cancelButton.keyEquivalent = "\u{1b}"
        cancelButton.target = self
        cancelButton.action = #selector(cancel)
        exportButton.keyEquivalent = "\r"
        exportButton.target = self
        exportButton.action = #selector(exportPressed)
        exportButton.isEnabled = false
        let buttons = NSStackView()
        buttons.spacing = 8
        for button in [cancelButton, exportButton] { buttons.addView(button, in: .trailing) }

        let column = NSStackView(views: [titleLabel, stepsStack, details, failureLabel, buttons])
        column.orientation = .vertical
        column.alignment = .leading
        column.spacing = 12
        column.setCustomSpacing(16, after: details)
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
            stepsStack.widthAnchor.constraint(equalTo: column.widthAnchor),
            details.widthAnchor.constraint(equalTo: column.widthAnchor),
            failureLabel.widthAnchor.constraint(lessThanOrEqualTo: column.widthAnchor),
            buttons.widthAnchor.constraint(equalTo: column.widthAnchor),
            spinner.leadingAnchor.constraint(equalTo: stepsStack.leadingAnchor),
            spinner.centerYAnchor.constraint(equalTo: stepRows[0].centerYAnchor),
        ])
        self.view = view
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        guard running == nil else { return }
        running = Task { await run() }
    }

    // MARK: The steps

    /// Draws each step when it arrives, and the counts and warnings in the third check's frame.
    /// Returns when the last check has been drawn.
    func run() async {
        let clock = ContinuousClock()
        let opened = clock.now
        spinnerDelay = Task { [spinner] in
            try? await Task.sleep(for: .milliseconds(150))
            if !Task.isCancelled { spinner.startAnimation(nil) }
        }
        var finished: [Duration] = []
        for await step in steps {
            finished.append(clock.now - opened)
            let index = finished.count - 1
            let delay = ExportStepReveal.starts(finishedAt: finished, reduceMotion: reduceMotion())[index] - finished[index]
            if delay <= .zero {
                reveal(step, at: index)
            } else {
                reveals.append(Task {
                    try? await Task.sleep(for: delay)
                    if !Task.isCancelled { reveal(step, at: index) }
                })
            }
        }
        for task in reveals { await task.value }
    }

    private func reveal(_ step: ExportStep, at index: Int) {
        spinnerDelay?.cancel()
        spinner.stopAnimation(nil)
        let row = stepRows[index]
        row.label.stringValue = model.text(of: step)
        if reduceMotion() {
            row.alphaValue = 1
        } else {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.15
                context.timingFunction = CAMediaTimingFunction(controlPoints: 0.23, 1, 0.32, 1)
                context.allowsImplicitAnimation = true
                row.animator().alphaValue = 1
            }
        }
        if case .scanned(let plan) = step { show(plan) }
    }

    /// The counts, the warnings and Export…, all in one frame: nothing is clickable before the
    /// credential warning is on screen.
    private func show(_ plan: ExportPlan) {
        self.plan = plan
        countsLabel.stringValue = model.counts(plan)
        for notice in model.notices(plan) {
            let names = PostmanImport.namesLine(notice.names, width: Self.bodyWidth - 22) { text in
                NSAttributedString(string: text, attributes: [.font: Self.namesFont]).size().width
            }
            let view = NoticeView(notice, names: names)
            noticeViews.append(view)
            details.addArrangedSubview(view)
        }
        details.isHidden = false
        exportButton.isEnabled = true
    }

    // MARK: Cancel, Export…

    @objc private func cancel() {
        endSheet(.cancel)
    }

    @objc private func exportPressed() {
        // At once: a second press before the task has run would ask for a second save panel.
        exportButton.isEnabled = false
        Task { await export() }
    }

    /// The save panel as a sheet on this one, then the plan's bytes written where it said. Cancel
    /// in the panel changes nothing; a failed write stays here as a red line and is never retried.
    func export() async {
        guard let plan, let sheetWindow = view.window else { return }
        exportButton.isEnabled = false
        defer { exportButton.isEnabled = true }
        guard let url = await choose(sheetWindow, model.fileName) else { return }
        do throws(StoreError) {
            try writer.write(plan.data, to: url)
        } catch {
            failureLabel.stringValue = model.failure(error)
            failureLabel.toolTip = failureLabel.stringValue
            failureLabel.isHidden = false
            return
        }
        failureLabel.isHidden = true
        onExported()
    }

    private func endSheet(_ response: NSApplication.ModalResponse) {
        if let panel = view.window, let parent = panel.sheetParent { parent.endSheet(panel, returnCode: response) }
    }

    /// The sheet has ended: nothing keeps reading or waiting.
    func stop() {
        running?.cancel()
        spinnerDelay?.cancel()
        reveals.forEach { $0.cancel() }
    }
}

private extension ExportSkip {
    var fileName: String { String(path.split(separator: "/").last ?? "") }
}

private extension [String] {
    /// One Request's findings sit together, so a repeat next to itself is the same Request; the same
    /// name further on is another Request and shows.
    func droppingRepeats() -> [String] {
        enumerated().filter { $0.offset == 0 || self[$0.offset - 1] != $0.element }.map(\.element)
    }
}

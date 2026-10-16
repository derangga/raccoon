import AppKit
import Observation
import RaccoonDomain

/// The status line over the body (design-system.md §6 Response viewer).
// ponytail: failed and notSent show the error as text until the send-failure states are built,
// and Body | Headers arrives with the Headers view.
final class ResponseViewer: NSView {
    private let model: TabModel
    private let theme: ThemeEnvironment

    let spinner = NSProgressIndicator()
    let codeLabel = NSTextField(labelWithString: "")
    let reasonLabel = NSTextField(labelWithString: "")
    let elapsedLabel = NSTextField(labelWithString: "")
    let sizeLabel = NSTextField(labelWithString: "")
    private let dot = NSTextField(labelWithString: "·")
    let prettyNote = NSTextField(labelWithString: ResponseBody.prettyOffNote)
    let mode = NSSegmentedControl(labels: ["Pretty", "Raw"], trackingMode: .selectOne, target: nil, action: nil)

    let textView: NSTextView
    private let layoutManager = NSLayoutManager()
    private let scroll = NSScrollView()
    let voidTitle = NSTextField(labelWithString: "")
    let voidText = NSTextField(wrappingLabelWithString: "")
    let keycap = NSTextField(labelWithString: "⌘↩")
    private let voidStack = NSStackView()

    /// Which text the view holds, so a render that changes nothing never swaps the storage.
    private var shown: (send: Int, presented: Bool, pretty: Bool)?
    private var ticking: Task<Void, Never>?
    /// The user's Pretty | Raw choice, kept apart from whether Pretty is possible right now.
    private var wantsPretty = true

    init(model: TabModel, theme: ThemeEnvironment) {
        self.model = model
        self.theme = theme
        // TextKit 1 with non-contiguous layout: TextKit 2 takes 19–36 s to scroll to the end of
        // 20 MB (environment-facts.md).
        let container = NSTextContainer(size: NSSize(width: CGFloat.greatestFiniteMagnitude, height: .greatestFiniteMagnitude))
        container.widthTracksTextView = false
        layoutManager.allowsNonContiguousLayout = true
        layoutManager.addTextContainer(container)
        NSTextStorage().addLayoutManager(layoutManager)
        textView = NSTextView(frame: .zero, textContainer: container)
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = theme.color(.backgroundRecessed).cgColor
        buildStatusLine()
        buildBody()
        render()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    // MARK: Layout

    private func buildStatusLine() {
        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.isDisplayedWhenStopped = false
        let bold = NSFont.monospacedSystemFont(ofSize: 12, weight: .bold)
        for label in [codeLabel, reasonLabel] { label.font = bold }
        reasonLabel.lineBreakMode = .byTruncatingTail
        // Only the reason truncates; the code, time and size never do.
        reasonLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        for label in [codeLabel, elapsedLabel, dot, sizeLabel, prettyNote] {
            label.setContentCompressionResistancePriority(.required, for: .horizontal)
        }
        for label in [elapsedLabel, sizeLabel] {
            label.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
            label.textColor = theme.color(.textSecondary)
        }
        dot.textColor = theme.color(.textTertiary)
        prettyNote.font = .systemFont(ofSize: 11)
        prettyNote.textColor = theme.color(.textDisabled)
        mode.selectedSegment = 0
        mode.target = self
        mode.action = #selector(modeChanged)
        mode.controlSize = .small
        mode.setContentCompressionResistancePriority(.required, for: .horizontal)

        let spacer = NSView()
        spacer.setContentHuggingPriority(.init(1), for: .horizontal)
        let row = NSStackView(views: [spinner, codeLabel, reasonLabel, elapsedLabel, dot, sizeLabel, spacer, prettyNote, mode])
        row.spacing = 10
        row.setCustomSpacing(6, after: codeLabel)
        row.edgeInsets = NSEdgeInsets(top: 0, left: 12, bottom: 0, right: 12)
        let rule = NSBox()
        rule.boxType = .custom
        rule.borderWidth = 0
        rule.fillColor = theme.color(.border)
        for view in [row, rule] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        NSLayoutConstraint.activate([
            row.topAnchor.constraint(equalTo: topAnchor),
            row.leadingAnchor.constraint(equalTo: leadingAnchor),
            row.trailingAnchor.constraint(equalTo: trailingAnchor),
            row.heightAnchor.constraint(equalToConstant: 34),
            rule.topAnchor.constraint(equalTo: row.bottomAnchor),
            rule.leadingAnchor.constraint(equalTo: leadingAnchor),
            rule.trailingAnchor.constraint(equalTo: trailingAnchor),
            rule.heightAnchor.constraint(equalToConstant: 1),
        ])
    }

    private func buildBody() {
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        textView.textContainerInset = NSSize(width: 8, height: 8)
        // Bodies never wrap: the view grows sideways and scrolls.
        textView.isHorizontallyResizable = true
        textView.isVerticallyResizable = true
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: .greatestFiniteMagnitude)
        textView.autoresizingMask = []
        scroll.documentView = textView
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false

        voidTitle.font = .systemFont(ofSize: 13, weight: .semibold)
        voidText.font = .systemFont(ofSize: 12)
        voidText.alignment = .center
        voidText.preferredMaxLayoutWidth = 440
        keycap.font = .systemFont(ofSize: 11)
        keycap.textColor = theme.color(.textSecondary)
        keycap.wantsLayer = true
        keycap.layer?.borderWidth = 1
        keycap.layer?.cornerRadius = 4
        keycap.layer?.borderColor = theme.color(.border).cgColor
        keycap.layer?.backgroundColor = theme.color(.background).cgColor
        voidStack.setViews([voidTitle, voidText, keycap], in: .center)
        voidStack.orientation = .vertical
        voidStack.spacing = 8

        for view in [scroll, voidStack] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: topAnchor, constant: 35),
            scroll.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            scroll.trailingAnchor.constraint(equalTo: trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: bottomAnchor),
            voidStack.centerXAnchor.constraint(equalTo: centerXAnchor),
            voidStack.centerYAnchor.constraint(equalTo: scroll.centerYAnchor),
            voidStack.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 16),
            voidStack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -16),
        ])
    }

    @objc private func modeChanged() {
        wantsPretty = mode.selectedSegment == 0
        render()
    }

    // MARK: Render

    /// Redraws from the Tab's Response state and presentation, and again whenever they change.
    func render() {
        withObservationTracking {
            draw(model.tab.response)
        } onChange: { [weak self] in
            Task { @MainActor in self?.render() }
        }
    }

    private func draw(_ state: ResponseState) {
        setStatus(nil)
        spinner.stopAnimation(nil)
        spinner.isHidden = true
        prettyNote.isHidden = true
        mode.isHidden = true
        switch state {
        case .idle:
            showVoid(title: nil, text: "Send a request to see the Response here.", keycap: true)
        case .sending(let since):
            // Nothing for 150 ms, so a fast local API never flashes a spinner.
            guard model.showsSpinner else {
                showVoid(title: nil, text: "", keycap: false)
                tick(after: .milliseconds(150))
                return
            }
            spinner.isHidden = false
            spinner.startAnimation(nil)
            setStatus(("Sending…", "", .textSecondary))
            elapsedLabel.stringValue = StatusLine.elapsed(model.now - since)
            elapsedLabel.isHidden = false
            showVoid(title: nil, text: "Waiting for the server.", keycap: false)
            tick(after: .milliseconds(100))
        case .received(let response):
            let line = StatusLine(status: response.status, elapsed: response.elapsed, byteCount: response.byteCount)
            setStatus((line.code, line.reason, line.token))
            elapsedLabel.stringValue = line.elapsed
            sizeLabel.stringValue = line.size
            [elapsedLabel, dot, sizeLabel].forEach { $0.isHidden = false }
            drawBody(response)
        case .failed(let error):
            setStatus(("Failed", "", .statusFailed))
            showVoid(title: "\(error)", text: "", keycap: false, failed: true)
        case .notSent(.invalidURL(let text)):
            setStatus(("Not sent", "", .statusFailed))
            showVoid(title: "Invalid URL", text: "After substitution the URL was \(text).", keycap: false, failed: true)
        case .notSent(.undefined(let names)):
            setStatus(("Not sent", "", .statusFailed))
            showVoid(title: "Not defined", text: names.map(\.rawValue).joined(separator: ", "), keycap: false, failed: true)
        }
    }

    private func drawBody(_ response: Response) {
        let presented = model.presented
        if response.byteCount == 0 { return showVoid(title: nil, text: "Empty body.", keycap: false) }
        if case .binary(let count) = presented?.body {
            let size = StatusLine(status: 0, elapsed: .zero, byteCount: count).size
            return showVoid(title: "Binary body", text: "\(size) that is not UTF-8 text. Raccoon shows text bodies only.", keycap: false)
        }
        voidStack.isHidden = true
        scroll.isHidden = false
        let canPretty: Bool = if case .pretty = presented?.body { true } else { false }
        mode.isHidden = false
        mode.setEnabled(canPretty, forSegment: 0)
        prettyNote.isHidden = response.byteCount <= ResponseBody.prettyThreshold
        let pretty = canPretty && wantsPretty
        mode.selectedSegment = pretty ? 0 : 1

        let key = (send: model.sends, presented: presented != nil, pretty: pretty)
        guard shown.map({ $0 != key }) ?? true else { return }
        shown = key
        // A new storage, never an in-place edit: replacing a large coloured storage's characters
        // ran past ten minutes at 1 MB (environment-facts.md).
        layoutManager.replaceTextStorage(NSTextStorage(attributedString: bodyText(response, presented, pretty: pretty)))
        textView.scrollToBeginningOfDocument(nil)
    }

    private func bodyText(_ response: Response, _ presented: TabModel.Presented?, pretty: Bool) -> NSAttributedString {
        let font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        if pretty, let presented, case .pretty(let text, _) = presented.body {
            let colored = NSMutableAttributedString(string: text, attributes: [.font: font, .foregroundColor: theme.color(.text)])
            for range in presented.ranges { colored.addAttribute(.foregroundColor, value: theme.color(range.token), range: range.range) }
            return colored
        }
        // Raw is the bytes as received: shown at once, before the presentation lands.
        let raw: String = if case .raw(let text) = presented?.body { text } else { String(decoding: response.body, as: UTF8.self) }
        return NSAttributedString(string: raw, attributes: [.font: font, .foregroundColor: theme.color(.text)])
    }

    private func setStatus(_ status: (code: String, reason: String, token: ColorToken)?) {
        codeLabel.stringValue = status?.code ?? ""
        reasonLabel.stringValue = status?.reason ?? ""
        for label in [codeLabel, reasonLabel] { label.textColor = theme.color(status?.token ?? .text) }
        reasonLabel.toolTip = status?.reason
        [elapsedLabel, dot, sizeLabel].forEach { $0.isHidden = true }
    }

    private func showVoid(title: String?, text: String, keycap showsKeycap: Bool, failed: Bool = false) {
        shown = nil
        scroll.isHidden = true
        voidStack.isHidden = false
        voidTitle.stringValue = title ?? ""
        voidTitle.isHidden = title == nil
        voidTitle.textColor = theme.color(failed ? .statusFailed : .textSecondary)
        voidText.stringValue = text
        voidText.textColor = theme.color(.textTertiary)
        keycap.isHidden = !showsKeycap
    }

    /// Time passing is not a change Observation sees, so look again while sending.
    private func tick(after delay: Duration) {
        guard ticking == nil else { return }
        ticking = Task { @MainActor [weak self] in
            try? await Task.sleep(for: delay)
            guard let self else { return }
            ticking = nil
            draw(model.tab.response)
        }
    }
}

import AppKit
import Observation
import RaccoonDomain

/// The status line over the body (design-system.md §6 Response viewer).
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
    let section = NSSegmentedControl(labels: ["Body", "Headers"], trackingMode: .selectOne, target: nil, action: nil)

    let textView: NSTextView
    private let layoutManager = NSLayoutManager()
    private let scroll = NSScrollView()
    let voidTitle = NSTextField(labelWithString: "")
    let voidText = NSTextField(wrappingLabelWithString: "")
    let keycap = NSTextField(labelWithString: "⌘↩")
    let failureGlyph = NSImageView()
    /// The one fix, when a failure has one; only an untrusted certificate does.
    let fixButton = NSButton()
    let voidStack = NSStackView()

    let headerList = NSScrollView()
    private let headerStack = NSStackView()
    private(set) var headerRows: [(name: NSTextField, value: NSTextField)] = []
    let noHeaders = NSTextField(labelWithString: "No headers.")
    /// Always under the last row: the transport merged and sorted them before Raccoon saw them.
    let headerNote = NSTextField(labelWithString: "macOS merges repeated headers and doesn't keep their order.")

    /// Which text the view holds, so a render that changes nothing never swaps the storage.
    private var shown: (send: Int, presented: Bool, pretty: Bool)?
    private var ticking: Task<Void, Never>?
    /// The user's Pretty | Raw choice, kept apart from whether Pretty is possible right now.
    private var wantsPretty = true
    private var wantsHeaders = false

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
        buildHeaders()
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
        section.selectedSegment = 0
        section.target = self
        section.action = #selector(sectionChanged)
        section.controlSize = .small
        section.setContentCompressionResistancePriority(.required, for: .horizontal)

        let spacer = NSView()
        spacer.setContentHuggingPriority(.init(1), for: .horizontal)
        let row = NSStackView(views: [spinner, codeLabel, reasonLabel, elapsedLabel, dot, sizeLabel, spacer, prettyNote, mode, section])
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
        failureGlyph.contentTintColor = theme.color(.statusFailed)
        failureGlyph.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            failureGlyph.widthAnchor.constraint(equalToConstant: 22),
            failureGlyph.heightAnchor.constraint(equalToConstant: 22),
        ])
        // backgroundElevated is the Send/Cancel fill; board 06 draws this one on background.
        fixButton.isBordered = false
        fixButton.wantsLayer = true
        fixButton.layer?.cornerRadius = 6
        fixButton.layer?.borderWidth = 1
        fixButton.layer?.borderColor = theme.color(.border).cgColor
        fixButton.layer?.backgroundColor = theme.color(.background).cgColor
        fixButton.title = "Allow insecure TLS for this request"
        fixButton.attributedTitle = NSAttributedString(string: fixButton.title, attributes: [
            .font: NSFont.systemFont(ofSize: 12), .foregroundColor: theme.color(.text),
        ])
        fixButton.target = self
        fixButton.action = #selector(allowInsecureTLS)
        fixButton.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            fixButton.heightAnchor.constraint(equalToConstant: 24),
            fixButton.widthAnchor.constraint(equalToConstant: fixButton.attributedTitle.size().width.rounded(.up) + 20),
        ])
        voidStack.setViews([failureGlyph, voidTitle, voidText, keycap, fixButton], in: .center)
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

    private func buildHeaders() {
        let mono = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        noHeaders.font = mono
        noHeaders.textColor = theme.color(.textTertiary)
        headerNote.font = .systemFont(ofSize: 11)
        headerNote.textColor = theme.color(.textTertiary)
        headerStack.orientation = .vertical
        headerStack.alignment = .leading
        headerStack.spacing = 0
        headerStack.translatesAutoresizingMaskIntoConstraints = false
        let document = FlippedView()
        document.translatesAutoresizingMaskIntoConstraints = false
        document.addSubview(headerStack)
        headerList.documentView = document
        headerList.hasVerticalScroller = true
        headerList.autohidesScrollers = true
        headerList.drawsBackground = false
        headerList.translatesAutoresizingMaskIntoConstraints = false
        addSubview(headerList)
        NSLayoutConstraint.activate([
            headerList.topAnchor.constraint(equalTo: topAnchor, constant: 35),
            headerList.leadingAnchor.constraint(equalTo: leadingAnchor),
            headerList.trailingAnchor.constraint(equalTo: trailingAnchor),
            headerList.bottomAnchor.constraint(equalTo: bottomAnchor),
            document.topAnchor.constraint(equalTo: headerList.contentView.topAnchor),
            document.leadingAnchor.constraint(equalTo: headerList.contentView.leadingAnchor),
            document.widthAnchor.constraint(equalTo: headerList.contentView.widthAnchor),
            headerStack.topAnchor.constraint(equalTo: document.topAnchor, constant: 8),
            headerStack.leadingAnchor.constraint(equalTo: document.leadingAnchor, constant: 12),
            headerStack.trailingAnchor.constraint(equalTo: document.trailingAnchor, constant: -12),
            headerStack.bottomAnchor.constraint(equalTo: document.bottomAnchor, constant: -8),
        ])
    }

    @objc private func allowInsecureTLS() { model.allowInsecureTLS() }

    @objc private func sectionChanged() {
        wantsHeaders = section.selectedSegment == 1
        render()
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
        section.isHidden = true
        headerList.isHidden = true
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
            showVoid(title: nil, text: "Waiting for the server. ⌘. cancels.", keycap: false)
            tick(after: .milliseconds(100))
        case .received(let response):
            let line = StatusLine(status: response.status, elapsed: response.elapsed, byteCount: response.byteCount)
            setStatus((line.code, line.reason, line.token))
            elapsedLabel.stringValue = line.elapsed
            sizeLabel.stringValue = line.size
            [elapsedLabel, dot, sizeLabel].forEach { $0.isHidden = false }
            section.isHidden = false
            section.setLabel("Headers \(response.headers.count)", forSegment: 1)
            section.selectedSegment = wantsHeaders ? 1 : 0
            if wantsHeaders { drawHeaders(response.headers) } else { drawBody(response) }
        case .failed(let error, let after):
            setStatus(("Failed", "", .statusFailed))
            elapsedLabel.stringValue = "after " + StatusLine.elapsed(after)
            elapsedLabel.isHidden = false
            let text = FailureText(error)
            showVoid(title: text.title, text: text.detail, keycap: false, failed: true)
            if case .untrustedCertificate = error { failureGlyph.image = Self.glyph("xmark.shield") }
            fixButton.isHidden = !text.offersInsecureTLS
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

    /// Two columns, name and value, in the order the transport returned them.
    private func drawHeaders(_ headers: [Response.Header]) {
        shown = nil
        scroll.isHidden = true
        voidStack.isHidden = true
        headerList.isHidden = false
        headerRows = headers.map { header in
            let name = NSTextField(labelWithString: header.name)
            let value = NSTextField(labelWithString: header.value)
            name.textColor = theme.color(.textSecondary)
            value.textColor = theme.color(.text)
            value.toolTip = header.value
            for label in [name, value] {
                label.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
                label.lineBreakMode = .byTruncatingTail
                label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            }
            return (name, value)
        }
        let rows = headerRows.map { row in
            let line = NSStackView(views: [row.name, row.value])
            line.spacing = 0
            line.edgeInsets = NSEdgeInsets(top: 4, left: 0, bottom: 4, right: 0)
            // The name column is 220 pt when there is room; the value truncates first.
            row.name.widthAnchor.constraint(lessThanOrEqualToConstant: 220).isActive = true
            let wide = row.name.widthAnchor.constraint(equalToConstant: 220)
            wide.priority = .init(260)
            wide.isActive = true
            row.value.setContentCompressionResistancePriority(.init(250), for: .horizontal)
            let rule = NSBox()
            rule.boxType = .custom
            rule.borderWidth = 0
            rule.fillColor = theme.color(.border)
            rule.heightAnchor.constraint(equalToConstant: 1).isActive = true
            let cell = NSStackView(views: [line, rule])
            cell.orientation = .vertical
            cell.spacing = 0
            return cell
        }
        noHeaders.isHidden = !headers.isEmpty
        headerStack.setViews(rows + [noHeaders, headerNote], in: .top)
        headerStack.setCustomSpacing(8, after: rows.last ?? noHeaders)
        for row in rows { row.widthAnchor.constraint(equalTo: headerStack.widthAnchor).isActive = true }
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
        headerList.isHidden = true
        scroll.isHidden = true
        voidStack.isHidden = false
        voidTitle.stringValue = title ?? ""
        voidTitle.isHidden = title == nil
        voidTitle.textColor = theme.color(failed ? .statusFailed : .textSecondary)
        voidText.stringValue = text
        voidText.textColor = theme.color(.textTertiary)
        keycap.isHidden = !showsKeycap
        failureGlyph.isHidden = !failed
        failureGlyph.image = Self.glyph("exclamationmark.circle")
        fixButton.isHidden = true
    }

    private static func glyph(_ name: String) -> NSImage? {
        NSImage(systemSymbolName: name, accessibilityDescription: nil)?.withSymbolConfiguration(.init(pointSize: 20, weight: .regular))
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

/// Lays the header rows out from the top of their scroll view.
private final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}

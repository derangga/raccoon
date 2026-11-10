import AppKit
import Observation
import RaccoonDomain

/// The status line, the Body toolbar and the body (design-system.md §6 Response viewer).
final class ResponseViewer: NSView {
    /// Row heights, each with a 1 pt rule under it.
    private enum Chrome {
        static let statusRow: CGFloat = 44
        static let toolbarRow: CGFloat = 38
        /// Where the body starts under the status line alone, and under the Body toolbar too.
        static let bodyTop = statusRow + 1
        static let bodyTopWithToolbar = bodyTop + toolbarRow + 1
    }

    private var model: TabModel
    private let theme: ThemeEnvironment

    let spinner = NSProgressIndicator()
    let codeLabel = NSTextField(labelWithString: "")
    let reasonLabel = NSTextField(labelWithString: "")
    let elapsedLabel = NSTextField(labelWithString: "")
    let sizeLabel = NSTextField(labelWithString: "")
    private let dot = NSTextField(labelWithString: "·")
    /// "· 2 redirects", after the size; hidden when the send followed none.
    private let redirectsDot = NSTextField(labelWithString: "·")
    let redirectsLabel = NSTextField(labelWithString: "")
    let prettyNote = NSTextField(labelWithString: ResponseBody.prettyOffNote)
    /// "Showing the first 1 MB of 3.2 MB", where the Pretty note sits, above the Hex view's limit.
    let hexNote = NSTextField(labelWithString: "")
    /// Beside `hexNote`, styled like `fixButton`; runs Save Response Body.
    let saveButton = NSButton()
    /// "900 × 900 · image/webp", where an image body is shown.
    let imageNote = NSTextField(labelWithString: "")
    let mode: SegmentedControl
    let section: SegmentedControl

    /// Under the status line in the Body section: Pretty | Raw and its note, then Search and Copy.
    let bodyToolbar = NSView()
    private let toolbarRule = NSBox()
    let searchButton: IconButton
    let copyButton: IconButton
    let findPanel: FindPanel
    /// `Chrome.bodyTop` under the status line alone, `bodyTopWithToolbar` under the Body toolbar too.
    private var scrollTop: NSLayoutConstraint!
    /// Left of a legacy scroller, or 16 pt in when scrollers overlay.
    private var findTrailing: NSLayoutConstraint!

    let textView: ResponseTextView
    let gutter: Gutter
    /// An image body, in the body's place: scaled down to fit, never up, centered.
    let imageView = NSImageView()
    private let layoutManager = NSLayoutManager()
    /// The layout manager does not retain its storage, so the view must.
    private var storage = NSTextStorage()
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
    let headerNote = NSTextField(labelWithString: TimelineText.headersNote)

    let timelineList = NSScrollView()
    private let timelineStack = NSStackView()
    /// Once at the end, when a Redirect's headers are drawn.
    let timelineNote = NSTextField(labelWithString: TimelineText.headersNote)

    /// Which text the view holds, so a render that changes nothing never swaps the storage.
    private var shown: (send: Int, presented: Bool, pretty: Bool)?
    /// The bound Tab's decoded image (nil inside: it did not decode), for the send that produced it.
    private var imageCache: (send: Int, image: NSImage?)?
    private var ticking: Task<Void, Never>?
    /// The user's Pretty | Raw choice, kept apart from whether Pretty is possible right now.
    private var wantsPretty = true
    /// The chosen section (Body, Headers, Timeline), kept across sends.
    private var wantsSection = Section.body

    private enum Section: Int { case body, headers, timeline }

    /// The whole coloured body for the current mode; the storage shows it with folds cut.
    private var body = NSAttributedString()
    /// What `body` was built from, so a new Flavor rebuilds it without reading the Tab.
    private var bodySource: (response: Response, presented: TabModel.Presented?, pretty: Bool)?
    private var regions: [FoldRegion] = []
    /// View state: every send and every Pretty | Raw switch starts unfolded.
    private var folds = FoldSet()
    private(set) var foldedText = FoldedText(regions: [], folds: FoldSet())

    /// Kept across opens, sends and Tabs; the matches are for the text shown now.
    private var findQuery = ""
    private var matches: FindMatches?
    private var currentMatch: Int?
    /// Counts searches, so a result for an older query or text is dropped when it lands.
    private var findRuns = 0
    private var finding: Task<Void, Never>?
    /// Where highlights are drawn now, in the storage's offsets, so they can be taken off.
    private var highlighted: [NSRange] = []
    private var scrolling: NSObjectProtocol?

    init(model: TabModel, theme: ThemeEnvironment) {
        self.model = model
        self.theme = theme
        // TextKit 1 with non-contiguous layout: TextKit 2 takes 19–36 s to scroll to the end of
        // 20 MB (environment-facts.md).
        let container = NSTextContainer(size: NSSize(width: CGFloat.greatestFiniteMagnitude, height: .greatestFiniteMagnitude))
        container.widthTracksTextView = false
        layoutManager.allowsNonContiguousLayout = true
        layoutManager.addTextContainer(container)
        storage.addLayoutManager(layoutManager)
        textView = ResponseTextView(frame: .zero, textContainer: container)
        gutter = Gutter(textView: textView, theme: theme)
        mode = SegmentedControl(labels: ["Pretty", "Raw"], style: .underline, theme: theme)
        section = SegmentedControl(labels: ["Body", "Headers", "Timeline"], style: .track, theme: theme)
        searchButton = IconButton(symbol: "magnifyingglass", label: "Find (⌘F)", theme: theme)
        copyButton = IconButton(symbol: "doc.on.doc", label: "Copy Response Body", theme: theme)
        findPanel = FindPanel(theme: theme)
        super.init(frame: .zero)
        wantsLayer = true
        buildStatusLine()
        buildBodyToolbar()
        buildBody()
        buildHeaders()
        buildTimeline()
        buildFind()
        theme.paint(self) { viewer, theme in
            viewer.layer?.backgroundColor = theme.color(.backgroundRecessed).cgColor
            viewer.recolorBody()
        }
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
        // The reason truncates first, then the redirects count goes; the code, time and size never do.
        reasonLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        for label in [codeLabel, elapsedLabel, dot, sizeLabel, redirectsDot, redirectsLabel] {
            label.setContentCompressionResistancePriority(.required, for: .horizontal)
        }
        for label in [elapsedLabel, sizeLabel, redirectsLabel] {
            label.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
            theme.paint(label) { $0.textColor = $1.color(.textSecondary) }
        }
        for separator in [dot, redirectsDot] { theme.paint(separator) { $0.textColor = $1.color(.textTertiary) } }
        section.selectedSegment = 0
        section.target = self
        section.action = #selector(sectionChanged)
        section.setContentCompressionResistancePriority(.required, for: .horizontal)

        // The sections lead; the Response's facts trail in every state, so they never move when one lands.
        let spacer = NSView()
        spacer.setContentHuggingPriority(.init(1), for: .horizontal)
        let row = NSStackView(views: [section, spacer, spinner, codeLabel, reasonLabel, elapsedLabel, dot, sizeLabel, redirectsDot, redirectsLabel])
        row.setVisibilityPriority(.detachOnlyIfNecessary, for: redirectsDot)
        row.setVisibilityPriority(.detachOnlyIfNecessary, for: redirectsLabel)
        row.spacing = 10
        row.setCustomSpacing(6, after: codeLabel)
        row.edgeInsets = NSEdgeInsets(top: 0, left: 12, bottom: 0, right: 12)
        let rule = NSBox()
        rule.boxType = .custom
        rule.borderWidth = 0
        theme.paint(rule) { $0.fillColor = $1.color(.border) }
        for view in [row, rule] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        NSLayoutConstraint.activate([
            row.topAnchor.constraint(equalTo: topAnchor),
            row.leadingAnchor.constraint(equalTo: leadingAnchor),
            row.trailingAnchor.constraint(equalTo: trailingAnchor),
            row.heightAnchor.constraint(equalToConstant: Chrome.statusRow),
            rule.topAnchor.constraint(equalTo: row.bottomAnchor),
            rule.leadingAnchor.constraint(equalTo: leadingAnchor),
            rule.trailingAnchor.constraint(equalTo: trailingAnchor),
            rule.heightAnchor.constraint(equalToConstant: 1),
        ])
    }

    private func buildBodyToolbar() {
        for note in [prettyNote, hexNote, imageNote] {
            note.font = .systemFont(ofSize: 11)
            note.lineBreakMode = .byTruncatingTail
            // The note is what gives way at a narrow width.
            note.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            theme.paint(note) { $0.textColor = $1.color(.textDisabled) }
        }
        mode.selectedSegment = 0
        mode.target = self
        mode.action = #selector(modeChanged)
        mode.setContentCompressionResistancePriority(.required, for: .horizontal)
        searchButton.target = self
        searchButton.action = #selector(openFind)
        copyButton.target = self
        copyButton.action = #selector(copyBody)

        let spacer = NSView()
        spacer.setContentHuggingPriority(.init(1), for: .horizontal)
        let row = NSStackView(views: [mode, prettyNote, hexNote, saveButton, imageNote, spacer, searchButton, copyButton])
        row.spacing = 10
        row.setCustomSpacing(4, after: searchButton)
        row.edgeInsets = NSEdgeInsets(top: 0, left: 12, bottom: 0, right: 12)
        toolbarRule.boxType = .custom
        toolbarRule.borderWidth = 0
        theme.paint(toolbarRule) { $0.fillColor = $1.color(.border) }
        for view in [bodyToolbar, row, toolbarRule] { view.translatesAutoresizingMaskIntoConstraints = false }
        bodyToolbar.addSubview(row)
        bodyToolbar.addSubview(toolbarRule)
        addSubview(bodyToolbar)
        NSLayoutConstraint.activate([
            bodyToolbar.topAnchor.constraint(equalTo: topAnchor, constant: Chrome.bodyTop),
            bodyToolbar.leadingAnchor.constraint(equalTo: leadingAnchor),
            bodyToolbar.trailingAnchor.constraint(equalTo: trailingAnchor),
            bodyToolbar.heightAnchor.constraint(equalToConstant: Chrome.toolbarRow + 1),
            row.topAnchor.constraint(equalTo: bodyToolbar.topAnchor),
            row.leadingAnchor.constraint(equalTo: bodyToolbar.leadingAnchor),
            row.trailingAnchor.constraint(equalTo: bodyToolbar.trailingAnchor),
            row.heightAnchor.constraint(equalToConstant: Chrome.toolbarRow),
            // The underline runs the row's full height, down to the rule.
            mode.heightAnchor.constraint(equalTo: row.heightAnchor),
            toolbarRule.topAnchor.constraint(equalTo: row.bottomAnchor),
            toolbarRule.leadingAnchor.constraint(equalTo: bodyToolbar.leadingAnchor),
            toolbarRule.trailingAnchor.constraint(equalTo: bodyToolbar.trailingAnchor),
            toolbarRule.heightAnchor.constraint(equalToConstant: 1),
        ])
    }

    /// Shown in the Body section of a received Response; `searchable` is false for an image.
    private func showToolbar(searchable: Bool) {
        bodyToolbar.isHidden = false
        scrollTop.constant = Chrome.bodyTopWithToolbar
        searchButton.isEnabled = searchable
        copyButton.isEnabled = searchable
    }

    private func hideToolbar() {
        bodyToolbar.isHidden = true
        scrollTop.constant = Chrome.bodyTop
    }

    private func buildBody() {
        textView.isEditable = false
        textView.isSelectable = true
        // The Find panel searches instead: the system bar insets the body and cannot see folded text.
        textView.usesFindBar = false
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
        scroll.verticalRulerView = gutter
        scroll.hasVerticalRuler = true
        scroll.rulersVisible = true
        textView.viewer = self
        gutter.toggle = { [weak self] region in self?.toggle(region) }

        voidTitle.font = .systemFont(ofSize: 13, weight: .semibold)
        voidText.font = .systemFont(ofSize: 12)
        voidText.alignment = .center
        voidText.preferredMaxLayoutWidth = 440
        keycap.font = .systemFont(ofSize: 11)
        keycap.wantsLayer = true
        keycap.layer?.borderWidth = 1
        keycap.layer?.cornerRadius = 4
        theme.paint(keycap) { keycap, theme in
            keycap.textColor = theme.color(.textSecondary)
            keycap.layer?.borderColor = theme.color(.border).cgColor
            keycap.layer?.backgroundColor = theme.color(.background).cgColor
        }
        theme.paint(failureGlyph) { $0.contentTintColor = $1.color(.statusFailed) }
        failureGlyph.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            failureGlyph.widthAnchor.constraint(equalToConstant: 22),
            failureGlyph.heightAnchor.constraint(equalToConstant: 22),
        ])
        // backgroundElevated is the Send/Cancel fill. This one sits on background.
        styleAsFixButton(fixButton, title: "Allow insecure TLS for this request")
        fixButton.target = self
        fixButton.action = #selector(allowInsecureTLS)
        // No target: Save Response Body goes up the responder chain to the AppDelegate.
        styleAsFixButton(saveButton, title: "Save to File…")
        saveButton.action = #selector(AppDelegate.saveResponseBody(_:))
        voidStack.setViews([failureGlyph, voidTitle, voidText, keycap, fixButton], in: .center)
        voidStack.orientation = .vertical
        voidStack.spacing = 8

        imageView.imageScaling = .scaleProportionallyDown
        imageView.imageAlignment = .alignCenter
        imageView.setContentCompressionResistancePriority(.init(1), for: .horizontal)
        imageView.setContentCompressionResistancePriority(.init(1), for: .vertical)
        imageView.setContentHuggingPriority(.init(1), for: .horizontal)
        imageView.setContentHuggingPriority(.init(1), for: .vertical)
        imageView.setAccessibilityLabel("Response image")
        imageView.menu = NSMenu()
        imageView.menu?.addItem(MainMenu.saveResponseBody())
        for view in [scroll, imageView, voidStack] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        scrollTop = scroll.topAnchor.constraint(equalTo: topAnchor, constant: Chrome.bodyTop)
        NSLayoutConstraint.activate([
            scrollTop,
            scroll.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            scroll.trailingAnchor.constraint(equalTo: trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: bottomAnchor),
            imageView.topAnchor.constraint(equalTo: scroll.topAnchor, constant: 8),
            imageView.leadingAnchor.constraint(equalTo: scroll.leadingAnchor, constant: 8),
            imageView.trailingAnchor.constraint(equalTo: scroll.trailingAnchor, constant: -8),
            imageView.bottomAnchor.constraint(equalTo: scroll.bottomAnchor, constant: -8),
            voidStack.centerXAnchor.constraint(equalTo: centerXAnchor),
            voidStack.centerYAnchor.constraint(equalTo: scroll.centerYAnchor),
            voidStack.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 16),
            voidStack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -16),
        ])
    }

    private func styleAsFixButton(_ button: NSButton, title: String) {
        button.isBordered = false
        button.wantsLayer = true
        button.layer?.cornerRadius = 6
        button.layer?.borderWidth = 1
        button.title = title
        theme.paint(button) { button, theme in
            button.layer?.borderColor = theme.color(.border).cgColor
            button.layer?.backgroundColor = theme.color(.background).cgColor
            button.attributedTitle = NSAttributedString(string: button.title, attributes: [
                .font: NSFont.systemFont(ofSize: 12), .foregroundColor: theme.color(.text),
            ])
        }
        button.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            button.heightAnchor.constraint(equalToConstant: 24),
            button.widthAnchor.constraint(equalToConstant: button.attributedTitle.size().width.rounded(.up) + 20),
        ])
    }

    private func buildHeaders() {
        let mono = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        noHeaders.font = mono
        theme.paint(noHeaders) { $0.textColor = $1.color(.textTertiary) }
        headerNote.font = .systemFont(ofSize: 11)
        theme.paint(headerNote) { $0.textColor = $1.color(.textTertiary) }
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
            headerList.topAnchor.constraint(equalTo: topAnchor, constant: Chrome.bodyTop),
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

    @objc private func copyBody() {
        model.copyBody(pretty: bodySource?.pretty ?? false)
        copyButton.flash("checkmark", tooltip: "Copied", for: 1.5)
    }

    // MARK: Find

    private func buildFind() {
        findPanel.isHidden = true
        findPanel.onQuery = { [weak self] query in
            self?.findQuery = query
            self?.runFind()
        }
        findPanel.onStep = { [weak self] forward in self?.findStep(forward: forward) }
        findPanel.onClose = { [weak self] in self?.closeFind(focusingBody: true) }
        // Above the body, so it floats over the text and never moves it.
        addSubview(findPanel, positioned: .above, relativeTo: scroll)
        findTrailing = findPanel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16)
        NSLayoutConstraint.activate([findPanel.topAnchor.constraint(equalTo: scroll.topAnchor, constant: 8), findTrailing])
        scroll.contentView.postsBoundsChangedNotifications = true
        scrolling = NotificationCenter.default.addObserver(forName: NSView.boundsDidChangeNotification, object: scroll.contentView, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.highlightVisible() }
        }
    }

    /// 8 pt left of a legacy scroller; 16 pt in when scrollers overlay the text or there is none.
    override func layout() {
        super.layout()
        let scroller = scroll.verticalScroller
        let beside = scroll.scrollerStyle == .legacy && scroller.map { !$0.isHidden && $0.frame.width > 0 } ?? false
        let constant = -(beside ? (scroller?.frame.width ?? 0) + 8 : 16)
        if findTrailing.constant != constant { findTrailing.constant = constant }
    }

    var isFinding: Bool { !findPanel.isHidden }

    /// The Search button, ⌘F and Edit ▸ Find ▸ Find….
    @objc func openFind() {
        guard !bodyToolbar.isHidden, searchButton.isEnabled else { return }
        let wasOpen = isFinding
        findPanel.field.stringValue = findQuery
        findPanel.open()
        if !wasOpen { runFind() }
    }

    /// Next or previous: Return and ⇧Return in the field, ⌘G and ⇧⌘G, the chevrons.
    func findStep(forward: Bool) {
        guard isFinding else { return openFind() }
        guard let matches, let current = currentMatch else { return }
        currentMatch = matches.step(current, forward: forward)
        showCount()
        reveal(currentMatch ?? current)
    }

    /// Off the main actor: a query with no match scans 20 MB in 70 ms (environment-facts.md, Q14).
    private func runFind() {
        findRuns += 1
        let run = findRuns
        let query = findQuery
        let text = body.string
        // From the current match while typing, so adding a letter does not jump back to the top.
        let anchor = currentMatch.flatMap { matches?.ranges[$0].lowerBound } ?? foldedText.source(textView.selectedRange().location)
        finding?.cancel()
        finding = Task { @MainActor [weak self] in
            let found = await Self.match(query, in: text)
            guard let self, run == findRuns, isFinding else { return }
            matches = found
            currentMatch = found.first(atOrAfter: anchor)
            showCount()
            if let currentMatch { reveal(currentMatch) } else { highlightVisible() }
        }
    }

    @concurrent
    nonisolated private static func match(_ query: String, in text: String) async -> FindMatches {
        FindMatches(of: query, in: text as NSString)
    }

    private func showCount() {
        let count = matches?.count(current: currentMatch) ?? ""
        findPanel.show(count: count, canStep: !(matches?.ranges.isEmpty ?? true))
    }

    /// Opens only the folds the match is in, then brings it on screen.
    private func reveal(_ index: Int) {
        guard let match = matches?.ranges[index] else { return }
        let opened = folds.unfolding(match, in: regions)
        if opened != folds {
            folds = opened
            refold(keeping: nil)
        }
        textView.scrollRangeToVisible(shownRange(match))
        highlightVisible()
    }

    private func shownRange(_ match: Range<Int>) -> NSRange {
        let start = foldedText.display(match.lowerBound)
        return NSRange(location: start, length: foldedText.display(match.upperBound) - start)
    }

    /// Esc, the close button, or nothing left to search. Closing by hand leaves the current
    /// match selected in the body, so ⌘C copies it.
    func closeFind(focusingBody: Bool) {
        let selection = currentMatch.flatMap { matches?.ranges[$0] }.map(shownRange)
        findPanel.isHidden = true
        findRuns += 1
        finding?.cancel()
        matches = nil
        currentMatch = nil
        highlightVisible()
        guard focusingBody else { return }
        window?.makeFirstResponder(textView)
        if let selection { textView.setSelectedRange(selection) }
    }

    /// Takes the last highlights off and draws the matches in the visible range only: a
    /// one-letter query on 5 MB finds a million, and the text shows a screenful.
    private func highlightVisible() {
        for range in highlighted where NSMaxRange(range) <= storage.length {
            for key: NSAttributedString.Key in [.backgroundColor, .underlineStyle, .underlineColor] {
                layoutManager.removeTemporaryAttribute(key, forCharacterRange: range)
            }
        }
        highlighted = []
        guard isFinding, let matches, !matches.ranges.isEmpty, storage.length > 0, let container = textView.textContainer else { return }
        let visible = textView.visibleRect.offsetBy(dx: -textView.textContainerOrigin.x, dy: -textView.textContainerOrigin.y)
        let glyphs = layoutManager.glyphRange(forBoundingRect: visible, in: container)
        let characters = layoutManager.characterRange(forGlyphRange: glyphs, actualGlyphRange: nil)
        let source = foldedText.sourceRange(characters.location ..< NSMaxRange(characters))
        for index in matches.indices(overlapping: source) {
            let match = matches.ranges[index]
            let range = shownRange(match)
            // Inside a fold, all or part: not on screen as itself.
            guard range.length == match.count, foldedText.source(range.location) == match.lowerBound,
                  NSMaxRange(range) <= storage.length else { continue }
            let current = index == currentMatch
            layoutManager.addTemporaryAttribute(.backgroundColor, value: theme.color(current ? .findMatchCurrent : .findMatch), forCharacterRange: range)
            if current {
                layoutManager.addTemporaryAttributes([.underlineStyle: NSUnderlineStyle.single.rawValue, .underlineColor: theme.color(.accent)],
                                                     forCharacterRange: range)
            }
            highlighted.append(range)
        }
    }

    @objc private func sectionChanged() {
        wantsSection = Section(rawValue: section.selectedSegment) ?? .body
        render()
    }

    @objc private func modeChanged() {
        wantsPretty = mode.selectedSegment == 0
        render()
    }

    // MARK: Render

    /// The other Tab's Response gets its own storage; folds start open again.
    func bind(_ model: TabModel) {
        self.model = model
        shown = nil
        imageCache = nil
        render()
    }

    /// Redraws from the Tab's Response state and presentation, and again whenever they change,
    /// while it is still the bound one.
    func render() {
        let bound = model
        withObservationTracking {
            draw(model.tab.response)
        } onChange: { [weak self] in
            Task { @MainActor in if self?.model === bound { self?.render() } }
        }
    }

    private func draw(_ state: ResponseState) {
        drawState(state)
        // Nothing to search any more: Headers, Timeline, an image, or no body at all.
        if isFinding, bodyToolbar.isHidden || !searchButton.isEnabled { closeFind(focusingBody: false) }
    }

    private func drawState(_ state: ResponseState) {
        hideToolbar()
        setStatus(nil)
        spinner.stopAnimation(nil)
        spinner.isHidden = true
        prettyNote.isHidden = true
        hexNote.isHidden = true
        saveButton.isHidden = true
        imageNote.isHidden = true
        imageView.isHidden = true
        mode.isHidden = true
        section.isHidden = true
        headerList.isHidden = true
        timelineList.isHidden = true
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
            let line = StatusLine(status: response.status, elapsed: response.elapsed, byteCount: response.byteCount,
                                  redirects: response.redirects.count)
            setStatus((line.code, line.reason, line.token))
            elapsedLabel.stringValue = line.elapsed
            sizeLabel.stringValue = line.size
            [elapsedLabel, dot, sizeLabel].forEach { $0.isHidden = false }
            redirectsLabel.stringValue = line.redirects
            [redirectsDot, redirectsLabel].forEach { $0.isHidden = line.redirects.isEmpty }
            section.isHidden = false
            section.setCount(response.headers.count, forSegment: 1)
            section.selectedSegment = wantsSection.rawValue
            switch wantsSection {
            case .body: drawBody(response)
            case .headers: drawHeaders(response.headers)
            case .timeline: drawTimeline(response)
            }
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
        // The Hex view when it has landed, else the old void; a binary body is empty until it lands.
        // present() always fills hex for a binary body.
        if case .binary = presented?.body { return showText(response, presented) }
        // From the header, so an image never waits for the presentation behind a flash of its bytes as text.
        if let mediaType = ResponseBody.imageMediaType(response) {
            guard let image = decodedImage(response) else {
                // Nothing until the hex lands, as for any binary body.
                guard let presented else { return showVoid(title: nil, text: "", keycap: false) }
                return presented.hex == nil ? showBinary(response.byteCount) : showText(response, presented)
            }
            return showImage(image, mediaType: mediaType)
        }
        // Not UTF-8 and not yet known to be: the bytes as text would be garbage, so nothing until it lands.
        if presented == nil, String(validating: response.body, as: UTF8.self) == nil {
            return showVoid(title: nil, text: "", keycap: false)
        }
        showText(response, presented)
    }

    /// The text view: a text body with Pretty | Raw and its Gutter, or the Hex view, which has
    /// neither (the offset column is the address) and no folds.
    private func showText(_ response: Response, _ presented: TabModel.Presented?) {
        let hex = presented?.hex
        showToolbar(searchable: true)
        voidStack.isHidden = true
        scroll.isHidden = false
        scroll.rulersVisible = hex == nil
        let canPretty: Bool = if case .pretty = presented?.body { true } else { false }
        mode.isHidden = hex != nil
        mode.setEnabled(canPretty, forSegment: 0)
        prettyNote.isHidden = hex != nil || response.byteCount <= ResponseBody.prettyThreshold
        if let hex, hex.totalBytes > hex.shownBytes {
            let size = StatusLine(status: 0, elapsed: .zero, byteCount: hex.totalBytes).size
            hexNote.stringValue = "Showing the first \(HexDump.limit / 1_000_000) MB of \(size)"
            hexNote.isHidden = false
            saveButton.isHidden = false
        }
        let pretty = canPretty && wantsPretty
        mode.selectedSegment = pretty ? 0 : 1

        let key = (send: model.sends, presented: presented != nil, pretty: pretty)
        guard shown.map({ $0 != key }) ?? true else { return }
        shown = key
        // A new storage, never an in-place edit: replacing a large coloured storage's characters
        // ran past ten minutes at 1 MB (environment-facts.md).
        bodySource = (response, presented, pretty)
        body = bodyText(response, presented, pretty: pretty)
        regions = pretty ? presented?.regions ?? [] : []
        // Raw before the presentation lands has no numbers yet.
        gutter.lines = hex != nil ? nil : presented.map { pretty ? $0.lines : $0.rawLines }
        // The matches were for the old text; the search below finds them in this one.
        matches = nil
        currentMatch = nil
        folds = FoldSet()
        refold(keeping: nil)
        textView.scrollToBeginningOfDocument(nil)
        // An open panel keeps its query and searches the new text.
        if isFinding { runFind() }
    }

    /// Decoded once per send: Body | Headers, resizing and a Theme change redraw without decoding again.
    private func decodedImage(_ response: Response) -> NSImage? {
        if let imageCache, imageCache.send == model.sends { return imageCache.image }
        let image = NSImage(data: response.body)
        imageCache = (model.sends, image)
        return image
    }

    private func showBinary(_ byteCount: Int) {
        let size = StatusLine(status: 0, elapsed: .zero, byteCount: byteCount).size
        showVoid(title: "Binary body", text: "\(size) that is not UTF-8 text. Raccoon shows text bodies only.", keycap: false)
    }

    private func showImage(_ image: NSImage, mediaType: String) {
        shown = nil
        showToolbar(searchable: false)
        scroll.isHidden = true
        voidStack.isHidden = true
        imageView.image = image
        imageView.isHidden = false
        // The bitmap's pixels, not `image.size`, which is points and follows the file's DPI.
        let rep = image.representations.first
        let pixels = (rep?.pixelsWide ?? 0) > 0 && (rep?.pixelsHigh ?? 0) > 0
            ? (rep?.pixelsWide ?? 0, rep?.pixelsHigh ?? 0) : (Int(image.size.width), Int(image.size.height))
        imageNote.stringValue = "\(pixels.0) × \(pixels.1) · \(mediaType)"
        imageNote.isHidden = false
    }

    /// The body in the current Flavor, keeping its folds, scroll and selection. The indent
    /// guides are drawn, so the text view redraws.
    private func recolorBody() {
        textView.needsDisplay = true
        guard shown != nil, let bodySource else { return }
        let place = textView.place
        body = bodyText(bodySource.response, bodySource.presented, pretty: bodySource.pretty)
        refold(keeping: nil)
        textView.restore(place)
    }

    // MARK: Folding

    /// Swaps in the body with each outermost Folded region cut to the marker, keeping
    /// `anchor`'s line where it was on screen.
    private func refold(keeping anchor: Int?) {
        let offset = anchor.map { top(of: $0) - scroll.contentView.bounds.minY }
        let x = scroll.contentView.bounds.minX
        foldedText = FoldedText(regions: regions, folds: folds)
        storage = Self.cut(body, foldedText.folded, marker: marker)
        layoutManager.replaceTextStorage(storage)
        // Temporary attributes belong to the layout manager, not the storage: clear any for the new text.
        highlighted = highlighted.isEmpty ? [] : [NSRange(location: 0, length: storage.length)]
        gutter.show(regions: regions, folds: folds, shown: foldedText)
        defer { highlightVisible() }
        guard let anchor, let offset, let lines = gutter.lines else { return }
        let at = foldedText.display(lines.starts[anchor])
        textView.setSelectedRange(NSRange(location: at, length: 0))
        // A fresh storage is laid out from the top only, so the view is too short and the
        // anchor's position a guess (y 169 for line 69) until the view scrolls to it.
        textView.scrollRangeToVisible(NSRange(location: at, length: 0))
        textView.scroll(NSPoint(x: x, y: top(of: anchor) - offset))
    }

    private func top(of line: Int) -> CGFloat {
        guard let lines = gutter.lines, storage.length > 0 else { return 0 }
        let glyph = layoutManager.glyphIndexForCharacter(at: min(foldedText.display(lines.starts[line]), storage.length - 1))
        return layoutManager.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil).minY
    }

    /// " … ", the `…` on `selection`.
    private var marker: NSAttributedString {
        let font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        let marker = NSMutableAttributedString(string: FoldedText.marker, attributes: [.font: font, .foregroundColor: theme.color(.text)])
        marker.addAttributes([.foregroundColor: theme.color(.textSecondary), .backgroundColor: theme.color(.selection)], range: NSRange(location: 1, length: 1))
        return marker
    }

    /// Few cuts are replaced in a copy from the back; many are built from small pieces, because
    /// appending a large piece to a non-empty string is slow (environment-facts.md).
    static func cut(_ body: NSAttributedString, _ folded: [FoldRegion], marker: NSAttributedString) -> NSTextStorage {
        precondition(folded.last.map { $0.cut.upperBound <= body.length } ?? true, "a Folded region past the end of the body")
        guard folded.count >= 64 else {
            let text = NSTextStorage(attributedString: body)
            for region in folded.reversed() { text.replaceCharacters(in: NSRange(region.cut), with: marker) }
            return text
        }
        let text = NSMutableAttributedString()
        var at = 0
        for region in folded {
            text.append(body.attributedSubstring(from: NSRange(at..<region.cut.lowerBound)))
            text.append(marker)
            at = region.cut.upperBound
        }
        text.append(body.attributedSubstring(from: NSRange(at..<body.length)))
        return NSTextStorage(attributedString: text)
    }

    private func toggle(_ region: FoldRegion) {
        folds.toggle(region)
        refold(keeping: region.openLine)
    }

    /// A click on a line's chevron.
    func toggleFold(line: Int) {
        guard let region = regions.first(where: { $0.openLine == line }) else { return }
        toggle(region)
    }

    /// A click on a `…`; false when `index` is not on one.
    func unfold(atMarker index: Int) -> Bool {
        guard let region = foldedText.region(atMarker: index) else { return false }
        toggle(region)
        return true
    }

    @objc func foldAtCaret(_ sender: Any?) { atCaret(folded: false) }
    @objc func unfoldAtCaret(_ sender: Any?) { atCaret(folded: true) }

    private func atCaret(folded: Bool) {
        guard let lines = gutter.lines else { return }
        let line = lines.line(containing: foldedText.source(textView.selectedRange().location))
        guard let region = folds.innermost(at: line, in: regions, folded: folded) else { return }
        toggle(region)
    }

    @objc func foldAll(_ sender: Any?) {
        let top = gutter.rows().first?.line
        folds = FoldSet(folding: regions)
        refold(keeping: top)
    }

    @objc func unfoldAll(_ sender: Any?) {
        let top = gutter.rows().first?.line
        folds = FoldSet()
        refold(keeping: top)
    }

    var gutterGuideColor: NSColor { theme.color(.border) }

    /// Pretty with at least one Fold Region.
    var canFold: Bool { !regions.isEmpty }

    /// The context menu's folding items, in Pretty only.
    func foldItems() -> [NSMenuItem] {
        guard canFold else { return [] }
        let items = [("Fold", "[", #selector(foldAtCaret)), ("Unfold", "]", #selector(unfoldAtCaret)),
                     ("Fold All", "", #selector(foldAll)), ("Unfold All", "", #selector(unfoldAll))].map { title, key, action in
            let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
            item.keyEquivalentModifierMask = [.command, .option]
            item.target = self
            return item
        }
        return items
    }

    /// The body text a shown selection covers, folded lines included.
    func bodyText(of selection: NSRange) -> String {
        (body.string as NSString).substring(with: NSRange(foldedText.sourceRange(selection.location ..< NSMaxRange(selection))))
    }

    /// Two columns, name and value, in the order the transport returned them.
    private func drawHeaders(_ headers: [Response.Header]) {
        shown = nil
        scroll.isHidden = true
        voidStack.isHidden = true
        headerList.isHidden = false
        headerRows = headers.map(headerLabels)
        let rows = headerRows.map(headerRow)
        noHeaders.isHidden = !headers.isEmpty
        headerStack.setViews(rows + [noHeaders, headerNote], in: .top)
        headerStack.setCustomSpacing(8, after: rows.last ?? noHeaders)
        for row in rows { row.widthAnchor.constraint(equalTo: headerStack.widthAnchor).isActive = true }
    }

    private func headerLabels(_ header: Response.Header) -> (name: NSTextField, value: NSTextField) {
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

    /// One row of a two-column list with its rule underneath: Headers and the Timeline draw alike.
    private func headerRow(_ row: (name: NSTextField, value: NSTextField)) -> NSView {
        let line = NSStackView(views: [row.name, row.value])
        line.spacing = 0
        line.distribution = .fill
        line.alignment = .firstBaseline
        line.edgeInsets = NSEdgeInsets(top: 4, left: 0, bottom: 4, right: 0)
        // The name column is 220 pt when there is room; the value takes the rest and truncates first.
        row.name.widthAnchor.constraint(lessThanOrEqualToConstant: 220).isActive = true
        let wide = row.name.widthAnchor.constraint(equalToConstant: 220)
        wide.priority = .init(750)
        wide.isActive = true
        row.value.setContentHuggingPriority(.init(1), for: .horizontal)
        row.value.setContentCompressionResistancePriority(.init(250), for: .horizontal)
        let rule = NSBox()
        rule.boxType = .custom
        rule.borderWidth = 0
        rule.fillColor = theme.color(.border)
        rule.heightAnchor.constraint(equalToConstant: 1).isActive = true
        let cell = NSStackView(views: [line, rule])
        cell.orientation = .vertical
        cell.alignment = .leading
        cell.spacing = 0
        line.widthAnchor.constraint(equalTo: cell.widthAnchor).isActive = true
        rule.widthAnchor.constraint(equalTo: cell.widthAnchor).isActive = true
        return cell
    }

    // MARK: Timeline

    private func buildTimeline() {
        timelineNote.font = .systemFont(ofSize: 11)
        theme.paint(timelineNote) { $0.textColor = $1.color(.textTertiary) }
        timelineStack.orientation = .vertical
        timelineStack.alignment = .leading
        timelineStack.spacing = 0
        timelineStack.translatesAutoresizingMaskIntoConstraints = false
        let document = FlippedView()
        document.translatesAutoresizingMaskIntoConstraints = false
        document.addSubview(timelineStack)
        timelineList.documentView = document
        timelineList.hasVerticalScroller = true
        timelineList.autohidesScrollers = true
        timelineList.drawsBackground = false
        timelineList.translatesAutoresizingMaskIntoConstraints = false
        addSubview(timelineList)
        NSLayoutConstraint.activate([
            timelineList.topAnchor.constraint(equalTo: topAnchor, constant: Chrome.bodyTop),
            timelineList.leadingAnchor.constraint(equalTo: leadingAnchor),
            timelineList.trailingAnchor.constraint(equalTo: trailingAnchor),
            timelineList.bottomAnchor.constraint(equalTo: bottomAnchor),
            document.topAnchor.constraint(equalTo: timelineList.contentView.topAnchor),
            document.leadingAnchor.constraint(equalTo: timelineList.contentView.leadingAnchor),
            document.widthAnchor.constraint(equalTo: timelineList.contentView.widthAnchor),
            timelineStack.topAnchor.constraint(equalTo: document.topAnchor, constant: 8),
            timelineStack.leadingAnchor.constraint(equalTo: document.leadingAnchor, constant: 12),
            timelineStack.trailingAnchor.constraint(equalTo: document.trailingAnchor, constant: -12),
            timelineStack.bottomAnchor.constraint(equalTo: document.bottomAnchor, constant: -8),
        ])
    }

    /// Each Redirect, then the Response, as `TimelineText` words them, separated by a rule.
    private func drawTimeline(_ response: Response) {
        shown = nil
        scroll.isHidden = true
        voidStack.isHidden = true
        timelineList.isHidden = false
        var views: [NSView] = []
        for (index, block) in TimelineText.blocks(response).enumerated() {
            if index > 0 { views.append(blockRule()) }
            views.append(titleLabel(block))
            views += [(block.phases, ColorToken.textSecondary), (block.connection, .textTertiary), (block.size, .textSecondary)]
                .compactMap { text, token in text.map { detailLabel($0, token) } }
            views += block.rows.map { headerRow(headerLabels($0)) }
        }
        let notes: [NSView] = TimelineText.showsHeadersNote(response) ? [timelineNote] : []
        timelineStack.setViews(views + notes, in: .top)
        for (view, next) in zip(views, views.dropFirst()) where view is NSBox || next is NSBox {
            timelineStack.setCustomSpacing(8, after: view)
        }
        if let last = views.last, !notes.isEmpty { timelineStack.setCustomSpacing(8, after: last) }
        // Every row and rule spans the list; the title and the note keep their own width.
        for view in views where !(view is NSTextField) { view.widthAnchor.constraint(equalTo: timelineStack.widthAnchor).isActive = true }
    }

    /// "302 Found" in its status color, then the rest of the first line in the text color.
    private func titleLabel(_ block: TimelineText.Block) -> NSTextField {
        let mono = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        let title = NSMutableAttributedString(string: block.line, attributes: [.font: mono, .foregroundColor: theme.color(.text)])
        title.addAttributes([.font: NSFont.monospacedSystemFont(ofSize: 12, weight: .bold), .foregroundColor: theme.color(block.token)],
                            range: NSRange(location: 0, length: (block.statusText as NSString).length))
        let label = NSTextField(labelWithAttributedString: title)
        label.lineBreakMode = .byTruncatingTail
        label.toolTip = block.line
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return label
    }

    /// A Timeline line under the title: phases, connection or size, in SF Mono 12 like the rest.
    private func detailLabel(_ text: String, _ token: ColorToken) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        label.textColor = theme.color(token)
        label.lineBreakMode = .byTruncatingTail
        label.toolTip = text
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return label
    }

    private func blockRule() -> NSBox {
        let rule = NSBox()
        rule.boxType = .custom
        rule.borderWidth = 0
        rule.fillColor = theme.color(.border)
        rule.heightAnchor.constraint(equalToConstant: 1).isActive = true
        return rule
    }

    private func bodyText(_ response: Response, _ presented: TabModel.Presented?, pretty: Bool) -> NSAttributedString {
        let font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        let text = NSMutableAttributedString(string: TabModel.shownText(response, presented, pretty: pretty),
                                             attributes: [.font: font, .foregroundColor: theme.color(.text)])
        // Only Pretty is coloured; its ranges are for exactly that text.
        if pretty, presented?.hex == nil, let presented, case .pretty = presented.body {
            for range in presented.ranges { text.addAttribute(.foregroundColor, value: theme.color(range.token), range: range.range) }
        }
        return text
    }

    private func setStatus(_ status: (code: String, reason: String, token: ColorToken)?) {
        codeLabel.stringValue = status?.code ?? ""
        reasonLabel.stringValue = status?.reason ?? ""
        for label in [codeLabel, reasonLabel] { label.textColor = theme.color(status?.token ?? .text) }
        reasonLabel.toolTip = status?.reason
        [elapsedLabel, dot, sizeLabel, redirectsDot, redirectsLabel].forEach { $0.isHidden = true }
    }

    private func showVoid(title: String?, text: String, keycap showsKeycap: Bool, failed: Bool = false) {
        shown = nil
        headerList.isHidden = true
        timelineList.isHidden = true
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
final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}

/// The Response body's text view: Copy reads the body behind the folds, a click on a `…`
/// unfolds it, and ⌥⌘[ / ⌥⌘] fold and unfold at the caret.
final class ResponseTextView: NSTextView {
    weak var viewer: ResponseViewer?
    var pasteboard = NSPasteboard.general

    override func copy(_ sender: Any?) {
        guard let viewer, !viewer.foldedText.folded.isEmpty, selectedRange().length > 0 else { return super.copy(sender) }
        pasteboard.clearContents()
        pasteboard.setString(viewer.bodyText(of: selectedRange()), forType: .string)
    }

    /// Edit ▸ Find's Find…, Find Next and Find Previous go to the viewer's Find panel.
    override func performTextFinderAction(_ sender: Any?) {
        guard let viewer, let tag = (sender as? NSValidatedUserInterfaceItem)?.tag else { return }
        switch NSTextFinder.Action(rawValue: tag) {
        case .showFindInterface: viewer.openFind()
        case .nextMatch: viewer.findStep(forward: true)
        case .previousMatch: viewer.findStep(forward: false)
        default: break
        }
    }

    /// With no system find bar, NSTextView would disable the Find items; the panel takes these three.
    override func validateMenuItem(_ item: NSMenuItem) -> Bool {
        guard item.action == #selector(performTextFinderAction(_:)) else { return super.validateMenuItem(item) }
        return Self.findActions.contains(item.tag)
    }

    override func validateUserInterfaceItem(_ item: NSValidatedUserInterfaceItem) -> Bool {
        guard item.action == #selector(performTextFinderAction(_:)) else { return super.validateUserInterfaceItem(item) }
        return Self.findActions.contains(item.tag)
    }

    private static let findActions: Set<Int> = [NSTextFinder.Action.showFindInterface, .nextMatch, .previousMatch].map(\.rawValue).reduce(into: []) { $0.insert($1) }

    /// The indent guides, under the text.
    override func drawBackground(in rect: NSRect) {
        super.drawBackground(in: rect)
        guard let viewer, let font, let container = textContainer else { return }
        let column = NSAttributedString(string: " ", attributes: [.font: font]).size().width
        viewer.gutterGuideColor.setFill()
        for guide in viewer.gutter.guides() {
            let x = (textContainerOrigin.x + container.lineFragmentPadding + CGFloat(guide.indent) * column).rounded(.down)
            NSRect(x: x, y: guide.top, width: 1, height: guide.bottom - guide.top).intersection(rect).fill()
        }
    }

    override func mouseDown(with event: NSEvent) {
        if let viewer, let layout = layoutManager, let container = textContainer {
            let point = convert(event.locationInWindow, from: nil)
            let inContainer = NSPoint(x: point.x - textContainerOrigin.x, y: point.y - textContainerOrigin.y)
            let glyph = layout.glyphIndex(for: inContainer, in: container, fractionOfDistanceThroughGlyph: nil)
            if layout.boundingRect(forGlyphRange: NSRange(location: glyph, length: 1), in: container).contains(inContainer),
               viewer.unfold(atMarker: layout.characterIndexForGlyph(at: glyph)) { return }
        }
        super.mouseDown(with: event)
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = super.menu(for: event)
        if let items = viewer?.foldItems(), !items.isEmpty, let menu {
            menu.addItem(.separator())
            items.forEach(menu.addItem)
        }
        menu?.addItem(.separator())
        menu?.addItem(MainMenu.saveResponseBody())
        return menu
    }

    /// Only while the body has focus: a key equivalent reaches every view in the window.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard window?.firstResponder === self, let viewer, viewer.canFold,
              event.modifierFlags.intersection(.deviceIndependentFlagsMask) == [.command, .option] else {
            return super.performKeyEquivalent(with: event)
        }
        switch event.charactersIgnoringModifiers {
        case "[": viewer.foldAtCaret(nil)
        case "]": viewer.unfoldAtCaret(nil)
        default: return super.performKeyEquivalent(with: event)
        }
        return true
    }
}

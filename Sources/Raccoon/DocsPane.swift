import AppKit
import RaccoonDomain

/// The Docs section: one editor filling the pane, the Request's Docs styled as they are typed
/// (design-system.md §6 Docs pane). The marks stay in the text; matched ones are laid out with no
/// glyphs, and the Docs toolbar floats over the pane while the editor is focused.
final class DocsPane: NSView, NSTextViewDelegate {
    /// The text after each edit the user makes.
    var onChange: ((String) -> Void)?

    static let placeholder = "Notes for this Request, in markdown."

    private let theme: ThemeEnvironment
    let textView: DocsTextView
    private let scroll = NSScrollView()
    let toolbar: DocsToolbar
    /// 11 pt side inset with the 5 pt line padding: 16 pt in. The 56 pt top is the band the toolbar
    /// floats in (8 + 32 + 16), kept whether or not it shows, so showing it never moves the text.
    private static let inset = NSSize(width: 11, height: 56)
    private var editorFocused = false
    private var linking = false

    init(theme: ThemeEnvironment) {
        self.theme = theme
        // TextKit 1, as the other editors: the styling is attributes on the one storage.
        textView = DocsTextView(usingTextLayoutManager: false)
        toolbar = DocsToolbar(theme: theme, editor: textView)
        super.init(frame: .zero)
        textView.delegate = self
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.drawsBackground = false
        textView.usesFindBar = true
        textView.isIncrementalSearchingEnabled = true
        textView.isContinuousSpellCheckingEnabled = true
        // Typed text is saved as typed: a smart quote or dash would rewrite it.
        for substitution in [\NSTextView.isAutomaticQuoteSubstitutionEnabled, \.isAutomaticDashSubstitutionEnabled,
                             \.isAutomaticTextReplacementEnabled, \.isAutomaticSpellingCorrectionEnabled] {
            textView[keyPath: substitution] = false
        }
        textView.textContainerInset = Self.inset
        textView.textContainer?.widthTracksTextView = false
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: .greatestFiniteMagnitude)
        textView.setAccessibilityLabel("Docs")
        scroll.documentView = textView
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false
        scroll.translatesAutoresizingMaskIntoConstraints = false
        addSubview(scroll)
        toolbar.isHidden = true
        addSubview(toolbar)
        textView.layoutManager?.delegate = textView
        textView.theme = theme
        textView.onFocusChange = { [weak self] focused in
            self?.editorFocused = focused
            self?.updateToolbar()
        }
        textView.onLinkPopover = { [weak self] open in
            self?.linking = open
            self?.updateToolbar()
        }
        NSLayoutConstraint.activate([
            toolbar.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            toolbar.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            scroll.topAnchor.constraint(equalTo: topAnchor),
            scroll.leadingAnchor.constraint(equalTo: leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        theme.paint(self) { pane, theme in
            pane.textView.insertionPointColor = theme.color(.text)
            pane.textView.linkTextAttributes = [.foregroundColor: theme.color(.accent)]
            pane.textView.placeholderColor = theme.color(.textDisabled)
            pane.textView.quoteBarColor = theme.color(.border)
            pane.textView.cardFill = theme.color(.backgroundRecessed)
            pane.textView.cardBorder = theme.color(.border)
            pane.textView.labelColor = theme.color(.textTertiary)
            pane.style()
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// Text from outside (a Tab, an undo, a reload): the user's own typing is already in the
    /// editor and is left alone, caret and all.
    func setDocs(_ text: String) {
        guard textView.string != text else { return }
        // Typing undo is registered against the old text; its ranges mean nothing in the new.
        undoManager?.removeAllActions(withTarget: textView)
        if let storage = textView.textStorage { undoManager?.removeAllActions(withTarget: storage) }
        textView.string = text
        style()
        textView.scrollToBeginningOfDocument(nil)
    }

    func textDidChange(_ notification: Notification) {
        // Styling during composition would strip the marked-text attributes; the commit restyles.
        if !textView.hasMarkedText() { style() }
        refreshToolbar()
        onChange?(textView.string)
    }

    func textViewDidChangeSelection(_ notification: Notification) {
        refreshToolbar()
        // A code block's fences show only while the caret is in it: restyle when it enters or leaves one.
        if !textView.hasMarkedText(), textView.string == textView.markedUpText,
           textView.blockIndex(containing: textView.selectedRange().location) != textView.expandedBlock { style() }
    }

    /// A caret never rests inside a hidden mark.
    func textView(_ textView: NSTextView, willChangeSelectionFromCharacterRange old: NSRange, toCharacterRange new: NSRange) -> NSRange {
        self.textView.settle(new, from: old)
    }

    /// Shown while the editor is first responder or its Link popover is open; no animation.
    private func updateToolbar() {
        toolbar.isHidden = !(editorFocused || linking)
        refreshToolbar()
    }

    private func refreshToolbar() {
        guard !toolbar.isHidden else { return }
        toolbar.update(DocsEdit.state(textView.string, selection: textView.selectedRange()))
    }

    private static let body = NSFont.systemFont(ofSize: 13)
    private static let mono = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
    /// A shown fence is small so it fits the fixed fence line; a hidden one draws nothing.
    private static let fenceFont = NSFont.monospacedSystemFont(ofSize: 10, weight: .regular)
    static let fenceHeight: CGFloat = 14
    static let cardGap: CGFloat = 8
    /// List markers: tabular digits, so 1. and 2. are the same width and line up.
    private static let marker = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .regular)

    // shortcut: restyles all of the Docs per keystroke, O(n); upgrade if Docs grow past a few pages.
    private func style() {
        guard let storage = textView.textStorage else { return }
        let text = storage.string as NSString
        let all = NSRange(location: 0, length: text.length)
        var hidden = IndexSet(), blocks = IndexSet(), bullets = IndexSet(), quotes: [NSRange] = [], marks: [NSRange] = [], spans: [NSRange] = []
        var fences: [(range: NSRange, language: String?)] = []
        storage.beginEditing()
        storage.setAttributes([.font: Self.body, .foregroundColor: theme.color(.text), .paragraphStyle: Self.bodyParagraph], range: all)
        for styled in DocsStyle.ranges(storage.string) where NSMaxRange(styled.range) <= text.length {
            let range = styled.range
            // Inside a heading, emphasis keeps the heading's size: it builds on the font already there.
            let under = storage.attribute(.font, at: range.location, effectiveRange: nil) as? NSFont
            storage.addAttributes(attributes(for: styled.style), range: range)
            if let under, under.pointSize != Self.body.pointSize, styled.style == .bold || styled.style == .italic {
                storage.addAttribute(.font, value: styled.style == .bold ? NSFont.systemFont(ofSize: under.pointSize, weight: .semibold)
                                     : NSFontManager.shared.convert(under, toHaveTrait: .italicFontMask), range: range)
            }
            switch styled.style {
            case .bold, .italic, .strikethrough, .code, .link: spans.append(range)
            case .heading:
                let line = text.lineRange(for: range)
                storage.addAttribute(.paragraphStyle, value: Self.paragraph(spacing: 2, before: line.location > 0 ? 12 : 0, after: 4), range: line)
            case .fence(let language): fences.append((range, language))
            case .mark, .quoteMark:
                var end = NSMaxRange(range)
                // `## ` and `> ` hide their space too; a space after `**bold**` is text.
                if styled.style == .quoteMark || text.character(at: range.location) == 0x23 {
                    while end < text.length, [0x20, 0x09].contains(text.character(at: end)) { end += 1 }
                }
                hidden.insert(integersIn: range.location..<end)
                marks.append(NSRange(location: range.location, length: end - range.location))
                if styled.style == .quoteMark || text.character(at: range.location) == 0x23 { blocks.insert(integersIn: range.location..<end) }
                if styled.style == .quoteMark {
                    let line = text.lineRange(for: range)
                    quotes.append(line)
                    storage.addAttribute(.paragraphStyle, value: Self.paragraph(spacing: Self.bodySpacing, first: 16, head: 16), range: line)
                }
            case .listMarker:
                hang(range, in: storage, bullets: &bullets)
            default: break
            }
        }
        // Code blocks: a card each, with its fences hidden unless the caret is in it.
        let caret = textView.selectedRange().location
        var cards: [DocsCodeBlock] = []
        for index in stride(from: 0, to: fences.count, by: 2) {
            let open = fences[index], close = index + 1 < fences.count ? fences[index + 1] : nil
            let openLine = text.lineRange(for: open.range)
            let closeLine = close.map { text.lineRange(for: $0.range) }
            let end = close.map { NSMaxRange($0.range) } ?? text.length
            let region = NSRange(location: openLine.location, length: end - openLine.location)
            let expanded = caret >= region.location && caret <= NSMaxRange(region)
            let lines = NSRange(location: openLine.location, length: (closeLine.map(NSMaxRange) ?? text.length) - openLine.location)
            storage.addAttribute(.paragraphStyle, value: Self.paragraph(spacing: 3, first: 12, head: 12, tail: -12), range: lines)
            for (fence, line, isOpen) in [(open, openLine, true)] + (close.map { [($0, closeLine!, false)] } ?? []) {
                // A fence line is the card's top or bottom padding: one fixed height shown or hidden, so
                // the card never moves when the caret enters it. The 8 pt outside the card is its spacing.
                let fenceStyle = Self.paragraph(spacing: 0, first: 12, head: 12, tail: -12, before: isOpen ? Self.cardGap : 0,
                                                after: isOpen ? 0 : Self.cardGap, fixedHeight: Self.fenceHeight)
                storage.addAttributes([.font: Self.fenceFont, .paragraphStyle: fenceStyle], range: line)
                // Hidden fences keep their glyphs, drawn clear: a line of .null glyphs gets no fragment of
                // its own in TextKit 1 and folds into the code line. A caret on it is inside the block,
                // which shows the fences, so it needs no settling.
                storage.addAttribute(.foregroundColor, value: expanded ? theme.color(.textTertiary) : NSColor.clear, range: fence.range)
            }
            cards.append(DocsCodeBlock(region: region, language: open.language, expanded: expanded, closed: close != nil))
        }
        textView.codeBlocks = cards
        textView.hiddenMarks = hidden
        textView.blockMarks = blocks
        textView.markRanges = marks
        textView.spanRanges = spans
        textView.bulletMarks = bullets
        textView.quoteLines = quotes
        textView.markedUpText = storage.string
        storage.endEditing()
        textView.typingAttributes = [.font: Self.body, .foregroundColor: theme.color(.text), .paragraphStyle: Self.bodyParagraph]
        textView.needsDisplay = true
        // New marks (a setDocs, an undo, a `## ` just typed) can leave the caret inside one.
        let selected = textView.selectedRange()
        let settled = textView.settle(selected, from: selected, travel: nil)
        if settled != selected { textView.setSelectedRange(settled) }
    }

    /// A list line hangs: the marker in a 24 pt gutter from 4 pt in, the text from 28 pt, wrapped
    /// lines under the text. The space after the marker takes the kern that puts the text at 28;
    /// a numbered marker is pushed right so 9. and 10. end together.
    private func hang(_ marker: NSRange, in storage: NSTextStorage, bullets: inout IndexSet) {
        let text = storage.string as NSString
        let line = text.lineRange(for: marker)
        let first = text.character(at: marker.location)
        let isBullet = [0x2D, 0x2A, 0x2B].contains(first)
        if isBullet { bullets.insert(marker.location) }
        let shown = isBullet ? "•" : text.substring(with: marker)
        let width = (shown as NSString).size(withAttributes: [.font: Self.marker]).width
        let space = (" " as NSString).size(withAttributes: [.font: Self.body]).width
        let numbered = first >= 0x30 && first <= 0x39
        let start = numbered ? max(4, 28 - width - space) : 4
        let kern = numbered ? 0 : max(0, 28 - start - width - space)
        let gap = NSRange(location: NSMaxRange(marker), length: 1)
        if kern > 0, NSMaxRange(gap) <= text.length, text.character(at: gap.location) == 0x20 { storage.addAttribute(.kern, value: kern, range: gap) }
        storage.addAttribute(.paragraphStyle, value: Self.paragraph(spacing: Self.bodySpacing, first: start, head: 28), range: line)
    }

    private static let bodyParagraph = paragraph(spacing: DocsPane.bodySpacing)
    /// Below each body line: SF 13's natural 15.5 pt line plus this is about 19.5 pt.
    static let bodySpacing: CGFloat = 4

    /// `spacing` is added below each line: TextKit 1's lineHeightMultiple adds its extra above the
    /// glyphs, which sinks text to the bottom of its line.
    private static func paragraph(spacing: CGFloat, first: CGFloat = 0, head: CGFloat = 0, tail: CGFloat = 0,
                                  before: CGFloat = 0, after: CGFloat = 0, fixedHeight: CGFloat? = nil) -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.lineSpacing = spacing
        style.firstLineHeadIndent = first
        style.headIndent = head
        style.tailIndent = tail
        style.paragraphSpacingBefore = before
        style.paragraphSpacing = after
        if let fixedHeight {
            style.minimumLineHeight = fixedHeight
            style.maximumLineHeight = fixedHeight
        }
        return style
    }

    private func attributes(for style: DocsStyle.Style) -> [NSAttributedString.Key: Any] {
        switch style {
        case .mark: [.foregroundColor: theme.color(.textTertiary)]
        case .heading(let level): [.font: NSFont.systemFont(ofSize: [20, 17, 15][min(level, 3) - 1], weight: .semibold)]
        case .bold: [.font: NSFont.systemFont(ofSize: 13, weight: .semibold)]
        case .italic: [.font: NSFontManager.shared.convert(Self.body, toHaveTrait: .italicFontMask)]
        case .strikethrough: [.strikethroughStyle: NSUnderlineStyle.single.rawValue]
        case .code: [.font: Self.mono, .backgroundColor: theme.color(.backgroundRecessed)]
        case .codeBlock, .fence: [.font: Self.mono]
        case .listMarker: [.font: Self.marker, .foregroundColor: theme.color(.textSecondary)]
        case .quoteMark, .quote: [.foregroundColor: theme.color(.textSecondary)]
        case .link(let url):
            if let url, let target = URL(string: url) {
                [.foregroundColor: theme.color(.accent), .link: target, .toolTip: url]
            } else {
                [.foregroundColor: theme.color(.accent)]
            }
        }
    }
}

/// A fenced code block as the editor draws it: its card, from the opening fence's line to the
/// closing fence's end (or the text's), and whether the caret is in it, which shows its fences.
struct DocsCodeBlock: Equatable {
    var region: NSRange
    var language: String?
    var expanded: Bool
    var closed: Bool
}

/// The Docs editor: matched marks laid out with no glyphs, format commands, the placeholder
/// while empty, and ⌘-click opens a link.
final class DocsTextView: NSTextView, NSLayoutManagerDelegate, NSPopoverDelegate {
    var placeholderColor = NSColor.placeholderTextColor {
        didSet { needsDisplay = true }
    }
    var quoteBarColor = NSColor.separatorColor
    /// Set by the pane's styling, for `markedUpText`: character indexes that get no glyph, the
    /// `-` and `*` drawn as `•`, and the lines that carry a quote bar.
    var hiddenMarks = IndexSet()
    var bulletMarks = IndexSet()
    /// The hidden runs of a heading's or quote's line mark: the caret rests after them, never before.
    var blockMarks = IndexSet()
    /// Each hidden mark as DocsStyle gave it (a heading's or quote's with its space), and the text
    /// each emphasis, code or link span styles: Delete decides per mark and span, not per merged run.
    var markRanges: [NSRange] = []
    var spanRanges: [NSRange] = []
    var quoteLines: [NSRange] = []
    var codeBlocks: [DocsCodeBlock] = []
    var cardFill = NSColor.controlBackgroundColor
    var cardBorder = NSColor.separatorColor
    var labelColor = NSColor.tertiaryLabelColor
    /// Lines run at most this far (720 pt) from the leading padding, plus the padding each side.
    static let measure: CGFloat = 720
    var markedUpText = ""
    /// Fires when the editor gains or loses first responder: the Docs toolbar follows it.
    var onFocusChange: ((Bool) -> Void)?
    private(set) var linkPopover: NSPopover?
    /// Fires when the Link popover opens or closes: the toolbar stays while it is open.
    var onLinkPopover: ((Bool) -> Void)?
    var theme: ThemeEnvironment?

    override func becomeFirstResponder() -> Bool {
        let accepted = super.becomeFirstResponder()
        if accepted { onFocusChange?(true) }
        return accepted
    }

    override func resignFirstResponder() -> Bool {
        let resigned = super.resignFirstResponder()
        if resigned { onFocusChange?(false) }
        return resigned
    }

    /// Esc ends editing: focus goes to the window, and the toolbar hides.
    override func cancelOperation(_ sender: Any?) {
        window?.makeFirstResponder(nil)
    }

    override func didChangeText() {
        super.didChangeText()
        needsDisplay = true
    }

    // MARK: Measure and code blocks

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        updateMeasure()
    }

    /// The text container is as wide as the pane allows, to the measure: a wider pane leaves the
    /// rest empty, and the selection highlight stops there too.
    func updateMeasure() {
        guard let container = textContainer, bounds.width > 0 else { return }
        let width = min(bounds.width - 2 * textContainerInset.width, Self.measure + 2 * container.lineFragmentPadding)
        if container.size.width != width { container.size = NSSize(width: max(width, 0), height: .greatestFiniteMagnitude) }
    }

    /// The block whose region holds `location`, ends included.
    func blockIndex(containing location: Int) -> Int? {
        codeBlocks.firstIndex { location >= $0.region.location && location <= NSMaxRange($0.region) }
    }

    /// The block the caret was in at the last restyle.
    var expandedBlock: Int? { codeBlocks.firstIndex(where: \.expanded) }

    /// Each card's rect in this view: from its opening fence line's fragment to its last line's,
    /// without the gap the fences keep outside it. Whole fragments, not used rects: a fence line
    /// whose glyphs are all hidden has an empty used rect.
    func cardRects() -> [NSRect] {
        guard let layout = layoutManager, let container = textContainer, let length = textStorage?.length, length > 0 else { return [] }
        let padding = container.lineFragmentPadding
        return codeBlocks.compactMap { block in
            guard NSMaxRange(block.region) <= length else { return nil }
            let top = layout.lineFragmentRect(forGlyphAt: layout.glyphIndexForCharacter(at: block.region.location), effectiveRange: nil)
            let last = max(block.region.location, NSMaxRange(block.region) - 1)
            let bottom = layout.lineFragmentRect(forGlyphAt: layout.glyphIndexForCharacter(at: last), effectiveRange: nil)
            let minY = top.minY + DocsPane.cardGap
            // An unclosed block ends on a code line, which keeps no gap below it.
            let maxY = bottom.maxY - (block.closed ? DocsPane.cardGap : 0)
            return NSRect(x: textContainerOrigin.x + padding, y: textContainerOrigin.y + minY,
                          width: container.size.width - 2 * padding, height: maxY - minY)
        }
    }

    private func drawCards() {
        for (block, rect) in zip(codeBlocks, cardRects()) {
            let card = NSBezierPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), xRadius: 6, yRadius: 6)
            cardFill.setFill()
            card.fill()
            cardBorder.setStroke()
            card.lineWidth = 1
            card.stroke()
            if !block.expanded, let language = block.language {
                let label = NSAttributedString(string: language, attributes: [.font: NSFont.monospacedSystemFont(ofSize: 10, weight: .regular), .foregroundColor: labelColor])
                label.draw(at: NSPoint(x: rect.maxX - 8 - label.size().width, y: rect.minY + 2))
            }
        }
    }

    // MARK: Hidden marks

    /// Where `new` may rest: no end of it inside a hidden mark, and none before a heading's or
    /// quote's line mark. An end moves to the edge in its direction of travel; a caret just after a
    /// line mark that moves left goes to the end of the previous line. With no `travel` (a restyle)
    /// a line mark's end is after it and any other mark's the nearer edge. While the text is ahead
    /// of `markedUpText` (mid-edit) nothing moves.
    func settle(_ new: NSRange, from old: NSRange, travel: Bool? = true) -> NSRange {
        guard string == markedUpText, !hiddenMarks.isEmpty else { return new }
        func direction(_ point: Int, _ before: Int) -> Bool? { travel == nil ? nil : point >= before }
        let start = snap(new.location, forward: direction(new.location, old.location), from: old.location)
        guard new.length > 0 else { return NSRange(location: start, length: 0) }
        let end = snap(NSMaxRange(new), forward: direction(NSMaxRange(new), NSMaxRange(old)), from: NSMaxRange(old))
        return NSRange(location: start, length: max(0, end - start))
    }

    private func snap(_ point: Int, forward: Bool?, from old: Int) -> Int {
        let text = string as NSString
        for run in hiddenMarks.rangeView {
            let block = blockMarks.contains(run.lowerBound)
            guard (run.lowerBound < point && point < run.upperBound) || (block && point == run.lowerBound) else { continue }
            if !block { return forward ?? (run.upperBound - point < point - run.lowerBound) ? run.upperBound : run.lowerBound }
            let lineStart = run.lowerBound > 0 && text.character(at: run.lowerBound - 1) == 0x0A
            // Only a Left arrow (one character back from the mark's edge) goes up a line: Home and a click stay.
            return forward == false && old == run.upperBound && old - point == 1 && lineStart ? run.lowerBound - 1 : run.upperBound
        }
        return point
    }

    func layoutManager(_ layoutManager: NSLayoutManager, shouldGenerateGlyphs glyphs: UnsafePointer<CGGlyph>,
                       properties props: UnsafePointer<NSLayoutManager.GlyphProperty>, characterIndexes charIndexes: UnsafePointer<Int>,
                       font aFont: NSFont, forGlyphRange glyphRange: NSRange) -> Int {
        // Mid-edit the indexes are the old text's: hide nothing until the restyle.
        guard textStorage?.string == markedUpText, !hiddenMarks.isEmpty || !bulletMarks.isEmpty else { return 0 }
        let count = glyphRange.length
        var properties = Array(UnsafeBufferPointer(start: props, count: count))
        var shown = Array(UnsafeBufferPointer(start: glyphs, count: count))
        var bullet = CGGlyph()
        var dot: UniChar = 0x2022
        CTFontGetGlyphsForCharacters(aFont, &dot, &bullet, 1)
        var changed = false
        for index in 0..<count {
            let character = charIndexes[index]
            if hiddenMarks.contains(character) {
                properties[index] = .null
                changed = true
            } else if bulletMarks.contains(character), bullet != 0 {
                shown[index] = bullet
                changed = true
            }
        }
        guard changed else { return 0 }
        layoutManager.setGlyphs(shown, properties: properties, characterIndexes: charIndexes, font: aFont, forGlyphRange: glyphRange)
        return count
    }

    // MARK: Format commands

    /// Runs `command` through DocsEdit and replaces the text as typing does: one undo step, named
    /// `name`, and `textDidChange` carries it to the Tab. False when DocsEdit declines.
    @discardableResult
    func perform(_ command: DocsEdit.Command, named name: String) -> Bool {
        guard !hasMarkedText(), let result = DocsEdit.apply(command, to: string, selection: selectedRange()) else { return false }
        replace(with: result.text, selection: result.selection, named: name)
        return true
    }

    /// Replaces only the span that differs, so undo puts back that span and a sensible caret.
    private func replace(with new: String, selection: NSRange, named name: String) {
        let old = string as NSString, new = new as NSString
        let shorter = min(old.length, new.length)
        var head = 0
        while head < shorter, old.character(at: head) == new.character(at: head) { head += 1 }
        var tail = 0
        while tail < shorter - head, old.character(at: old.length - 1 - tail) == new.character(at: new.length - 1 - tail) { tail += 1 }
        // Never split a surrogate pair.
        if head > 0, UTF16.isLeadSurrogate(old.character(at: head - 1)) { head -= 1 }
        if tail > 0, UTF16.isTrailSurrogate(old.character(at: old.length - tail)) { tail -= 1 }
        let span = NSRange(location: head, length: old.length - head - tail)
        if span.length > 0 || new.length != old.length {
            let replacement = new.substring(with: NSRange(location: head, length: new.length - head - tail))
            breakUndoCoalescing()
            guard shouldChangeText(in: span, replacementString: replacement) else { return }
            textStorage?.replaceCharacters(in: span, with: replacement)
            didChangeText()
            undoManager?.setActionName(name)
        }
        setSelectedRange(selection)
    }

    /// The target of every Format menu item, toolbar button and pull-down item; its tag says which.
    @objc func applyFormat(_ sender: Any?) {
        let tag = (sender as? NSMenuItem)?.tag ?? (sender as? NSControl)?.tag
        guard let format = tag.flatMap(DocsFormat.init(rawValue:)) else { return }
        if let command = format.command {
            perform(command, named: format.name)
        } else {
            askForLink()
        }
    }

    override func insertNewline(_ sender: Any?) {
        if !perform(.newline, named: "Typing") { super.insertNewline(sender) }
    }

    override func deleteBackward(_ sender: Any?) {
        guard !hasMarkedText() else { return super.deleteBackward(sender) }
        guard selectedRange().length == 0 else {
            if deleteSelection() { return }
            return super.deleteBackward(sender)
        }
        if deleteBeforeHiddenMarks() || perform(.deleteBackward, named: "Typing") { return }
        super.deleteBackward(sender)
    }

    override func deleteForward(_ sender: Any?) {
        if !hasMarkedText(), deleteSelection() { return }
        super.deleteForward(sender)
    }

    override func cut(_ sender: Any?) {
        guard selectedRange().length > 0, !hasMarkedText() else { return super.cut(sender) }
        copy(sender)
        if deleteSelection() { undoManager?.setActionName("Cut") } else { super.deleteBackward(sender) }
    }

    /// Deletes the selection through DocsEdit; false when there is none or it declines.
    private func deleteSelection() -> Bool {
        selectedRange().length > 0 && string == markedUpText && perform(.deleteSelection, named: "Typing")
    }

    /// With the caret right after hidden marks (`**b**|`, or `**a**~~|b~~`), Delete removes the
    /// visible character before them, not an invisible `*`; when that empties a styled span, its
    /// marks go too. Marks are taken one at a time, as DocsStyle gave them.
    private func deleteBeforeHiddenMarks() -> Bool {
        let caret = selectedRange().location
        let text = string as NSString
        func isBlock(_ mark: NSRange) -> Bool { blockMarks.contains(mark.location) }
        func mark(endingAt end: Int) -> NSRange? { markRanges.first { NSMaxRange($0) == end && !isBlock($0) } }
        guard string == markedUpText, let last = mark(endingAt: caret) else { return false }
        // The run of inline marks the caret sits after.
        var start = last.location
        while let before = mark(endingAt: start) { start = before.location }
        if start == 0 { return true }
        if markRanges.contains(where: { NSMaxRange($0) == start && isBlock($0) }) {
            // Just after a heading's or quote's mark: Delete takes that mark off.
            guard let result = DocsEdit.apply(.deleteBackward, to: string, selection: NSRange(location: start, length: 0)) else { return true }
            replace(with: result.text, selection: NSRange(location: result.selection.location + caret - start, length: 0), named: "Typing")
            return true
        }
        var cut = text.rangeOfComposedCharacterSequence(at: start - 1)
        // A span that this character is all of loses its marks with it.
        if let close = markRanges.first(where: { $0.location == start && !isBlock($0) }),
           let span = spanRanges.first(where: { NSMaxRange($0) == start && $0.location == cut.location }),
           let open = markRanges.first(where: { NSMaxRange($0) == span.location && !isBlock($0) }) {
            cut = NSRange(location: open.location, length: NSMaxRange(close) - open.location)
        }
        replace(with: text.replacingCharacters(in: cut, with: ""), selection: NSRange(location: caret - cut.length, length: 0), named: "Typing")
        return true
    }

    /// ⌘K or the toolbar's link button: Link and Text fields under the selection (the caret's line
    /// when nothing is selected). Link has focus. Return applies, Esc or a click outside closes.
    private func askForLink() {
        guard window != nil, let theme else { return }
        closeLinkPopover()
        let state = DocsEdit.state(string, selection: selectedRange())
        let selected = selectedRange().length > 0 ? (string as NSString).substring(with: selectedRange()) : ""
        let controller = LinkPopoverController(url: state.link ?? "", text: state.link == nil ? selected : state.linkText ?? "", theme: theme)
        let popover = NSPopover()
        popover.behavior = .transient
        popover.delegate = self
        popover.contentViewController = controller
        controller.onCancel = { [weak self] in self?.closeLinkPopover() }
        controller.onApply = { [weak self] url, text in
            guard let self else { return }
            closeLinkPopover()
            window?.makeFirstResponder(self)
            perform(.link(url: url, text: text), named: DocsFormat.link.name)
        }
        linkPopover = popover
        onLinkPopover?(true)
        // Below the selection in the view's own (flipped) coordinates; AppKit flips it above when there is no room.
        popover.show(relativeTo: selectionRect(), of: self, preferredEdge: .maxY)
        controller.view.window?.makeFirstResponder(controller.urlField)
    }

    private func closeLinkPopover() {
        let popover = linkPopover
        linkPopover = nil
        popover?.close()
        if popover != nil { onLinkPopover?(false) }
    }

    func popoverDidClose(_ notification: Notification) {
        guard let popover = notification.object as? NSPopover, popover === linkPopover else { return }
        closeLinkPopover()
    }

    /// The selection's rect in this view, or the caret's line when nothing is selected.
    func selectionRect() -> NSRect {
        guard let layout = layoutManager, let container = textContainer else { return bounds }
        let selection = selectedRange()
        let length = (string as NSString).length
        var rect: NSRect
        if selection.length > 0 {
            rect = layout.boundingRect(forGlyphRange: layout.glyphRange(forCharacterRange: selection, actualCharacterRange: nil), in: container)
        } else if selection.location == length, !layout.extraLineFragmentRect.isEmpty {
            rect = layout.extraLineFragmentRect
        } else if length > 0 {
            rect = layout.lineFragmentUsedRect(forGlyphAt: layout.glyphIndexForCharacter(at: min(selection.location, length - 1)), effectiveRange: nil)
        } else {
            rect = NSRect(x: 0, y: 0, width: 1, height: NSFont.systemFont(ofSize: 13).boundingRectForFont.height)
        }
        return rect.offsetBy(dx: textContainerOrigin.x, dy: textContainerOrigin.y)
    }

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        drawCards()
        super.draw(dirtyRect)
        drawQuoteBars()
        guard string.isEmpty else { return }
        let origin = NSPoint(x: textContainerInset.width + (textContainer?.lineFragmentPadding ?? 0), y: textContainerInset.height)
        NSAttributedString(string: DocsPane.placeholder, attributes: [.font: NSFont.systemFont(ofSize: 13), .foregroundColor: placeholderColor])
            .draw(at: origin)
    }

    /// The 2 pt bars, 4 pt in, over exactly each quote line's own line fragments. They are found
    /// from the line's first visible glyph: a hidden mark's glyph can sit in the line before.
    func quoteBarRects() -> [NSRect] {
        guard let layout = layoutManager, let container = textContainer, let length = textStorage?.length else { return [] }
        let text = string as NSString
        var rects: [NSRect] = []
        for line in quoteLines where NSMaxRange(line) <= length {
            var first = line.location
            while first < NSMaxRange(line) - 1, hiddenMarks.contains(first) { first += 1 }
            let glyphs = layout.glyphRange(forCharacterRange: NSRange(location: first, length: NSMaxRange(line) - first), actualCharacterRange: nil)
            layout.enumerateLineFragments(forGlyphRange: glyphs) { rect, _, _, fragmentGlyphs, _ in
                // A fragment before the line's own (the glyph range can start in the previous one) is skipped.
                guard NSMaxRange(layout.characterRange(forGlyphRange: fragmentGlyphs, actualGlyphRange: nil)) > first || text.length == 0 else { return }
                rects.append(NSRect(x: self.textContainerOrigin.x + container.lineFragmentPadding + 4, y: self.textContainerOrigin.y + rect.minY, width: 2, height: rect.height))
            }
        }
        return rects
    }

    private func drawQuoteBars() {
        quoteBarColor.setFill()
        quoteBarRects().forEach { $0.fill() }
    }

    override func mouseDown(with event: NSEvent) {
        guard event.modifierFlags.contains(.command), let layout = layoutManager, let container = textContainer, let storage = textStorage else {
            return super.mouseDown(with: event)
        }
        let point = convert(event.locationInWindow, from: nil)
        let inContainer = NSPoint(x: point.x - textContainerOrigin.x, y: point.y - textContainerOrigin.y)
        let index = layout.characterIndex(for: inContainer, in: container, fractionOfDistanceBetweenInsertionPoints: nil)
        guard index < storage.length, let url = storage.attribute(.link, at: index, effectiveRange: nil) as? URL else {
            return super.mouseDown(with: event)
        }
        NSWorkspace.shared.open(url)
    }
}

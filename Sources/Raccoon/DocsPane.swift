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
    private static let inset = NSSize(width: 11, height: 16)

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
        // With the 5 pt line padding: 16 pt in from the pane's sides and from its top.
        textView.textContainerInset = Self.inset
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
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
        textView.onFocusChange = { [weak self] focused in self?.setToolbar(shown: focused) }
        textView.onClickPlaced = { [weak self] in self?.applyInset() }
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

    func textViewDidChangeSelection(_ notification: Notification) { refreshToolbar() }

    /// A caret never rests inside a hidden mark.
    func textView(_ textView: NSTextView, willChangeSelectionFromCharacterRange old: NSRange, toCharacterRange new: NSRange) -> NSRange {
        self.textView.settle(new, from: old)
    }

    /// Hidden while the editor is not first responder; the text's top inset makes room while shown.
    private func setToolbar(shown: Bool) {
        toolbar.isHidden = !shown
        applyInset()
        refreshToolbar()
    }

    /// Not while a click is being placed: the text moving 40 pt under it would land the caret 40 pt
    /// off. The click's end applies it, and the clicked character moves with the text.
    private func applyInset() {
        guard !textView.isPlacingClick else { return }
        textView.textContainerInset = NSSize(width: Self.inset.width, height: Self.inset.height + (toolbar.isHidden ? 0 : 40))
    }

    private func refreshToolbar() {
        guard !toolbar.isHidden else { return }
        toolbar.update(DocsEdit.state(textView.string, selection: textView.selectedRange()))
    }

    private static let body = NSFont.systemFont(ofSize: 13)
    private static let mono = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)

    // shortcut: restyles all of the Docs per keystroke, O(n); upgrade if Docs grow past a few pages.
    private func style() {
        guard let storage = textView.textStorage else { return }
        let text = storage.string as NSString
        let all = NSRange(location: 0, length: text.length)
        var hidden = IndexSet(), blocks = IndexSet(), bullets = IndexSet(), quotes: [NSRange] = [], marks: [NSRange] = [], spans: [NSRange] = []
        storage.beginEditing()
        storage.setAttributes([.font: Self.body, .foregroundColor: theme.color(.text)], range: all)
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
            case .mark where text.substring(with: range).hasPrefix("```"):
                // A fence line stays, dimmed.
                storage.addAttribute(.font, value: Self.mono, range: range)
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
                    storage.addAttribute(.paragraphStyle, value: Self.quoteParagraph, range: line)
                }
            case .listMarker where [0x2D, 0x2A].contains(text.character(at: range.location)):
                bullets.insert(range.location)
            default: break
            }
        }
        textView.hiddenMarks = hidden
        textView.blockMarks = blocks
        textView.markRanges = marks
        textView.spanRanges = spans
        textView.bulletMarks = bullets
        textView.quoteLines = quotes
        textView.markedUpText = storage.string
        storage.endEditing()
        textView.typingAttributes = [.font: Self.body, .foregroundColor: theme.color(.text)]
        textView.needsDisplay = true
        // New marks (a setDocs, an undo, a `## ` just typed) can leave the caret inside one.
        let caret = textView.selectedRange()
        let settled = textView.settle(caret, from: caret, travel: nil)
        if settled != caret { textView.setSelectedRange(settled) }
    }

    private static let quoteParagraph: NSParagraphStyle = {
        let style = NSMutableParagraphStyle()
        style.firstLineHeadIndent = 12
        style.headIndent = 12
        return style
    }()

    private func attributes(for style: DocsStyle.Style) -> [NSAttributedString.Key: Any] {
        switch style {
        case .mark: [.foregroundColor: theme.color(.textTertiary)]
        case .heading(let level): [.font: NSFont.systemFont(ofSize: [20, 17, 15][min(level, 3) - 1], weight: .semibold)]
        case .bold: [.font: NSFont.systemFont(ofSize: 13, weight: .semibold)]
        case .italic: [.font: NSFontManager.shared.convert(Self.body, toHaveTrait: .italicFontMask)]
        case .strikethrough: [.strikethroughStyle: NSUnderlineStyle.single.rawValue]
        case .code, .codeBlock: [.font: Self.mono, .backgroundColor: theme.color(.backgroundRecessed)]
        case .listMarker, .quoteMark, .quote: [.foregroundColor: theme.color(.textSecondary)]
        case .link(let url):
            if let url, let target = URL(string: url) {
                [.foregroundColor: theme.color(.accent), .link: target, .toolTip: url]
            } else {
                [.foregroundColor: theme.color(.accent)]
            }
        }
    }
}

/// The Docs editor: matched marks laid out with no glyphs, format commands, the placeholder
/// while empty, and ⌘-click opens a link.
final class DocsTextView: NSTextView, NSLayoutManagerDelegate {
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
    var markedUpText = ""
    /// Fires when the editor gains or loses first responder: the Docs toolbar follows it.
    var onFocusChange: ((Bool) -> Void)?
    private(set) var linkPopover: NSPopover?
    /// True from the click that focuses the editor until its `mouseDown` ends; `onClickPlaced` fires then.
    private(set) var isPlacingClick = false
    var onClickPlaced: (() -> Void)?

    override func becomeFirstResponder() -> Bool {
        // The window focuses the editor before it delivers the click: the pane keeps the text where
        // it is until `mouseDown` has placed the caret.
        if let event = window?.currentEvent, event.type == .leftMouseDown,
           let hit = window?.contentView?.superview?.hitTest(event.locationInWindow), hit === self || hit.isDescendant(of: self) {
            holdInsetForClick()
        }
        let accepted = super.becomeFirstResponder()
        if accepted { onFocusChange?(true) }
        return accepted
    }

    func holdInsetForClick() {
        isPlacingClick = true
        releaseAfterMouseUp()
    }

    /// A fallback for a click whose `mouseDown` never ends the hold: once the button is up, it goes.
    private func releaseAfterMouseUp() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            guard let self, isPlacingClick else { return }
            if NSEvent.pressedMouseButtons & 1 != 0 { releaseAfterMouseUp() } else { endClick() }
        }
    }

    func endClick() {
        guard isPlacingClick else { return }
        isPlacingClick = false
        onClickPlaced?()
    }

    override func resignFirstResponder() -> Bool {
        isPlacingClick = false
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
        guard selectedRange().length == 0, !hasMarkedText() else { return super.deleteBackward(sender) }
        if deleteBeforeHiddenMarks() || perform(.deleteBackward, named: "Typing") { return }
        super.deleteBackward(sender)
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

    /// ⌘K or the toolbar's link button: a URL field under the selection, with the current link's
    /// URL or "https://". Return applies, Esc cancels.
    private func askForLink() {
        guard window != nil else { return }
        linkPopover?.close()
        let controller = LinkPopoverController(url: DocsEdit.state(string, selection: selectedRange()).link ?? "https://")
        let popover = NSPopover()
        popover.behavior = .transient
        popover.contentViewController = controller
        controller.onCancel = { [weak self, weak popover] in
            popover?.close()
            self?.window?.makeFirstResponder(self)
        }
        controller.onApply = { [weak self, weak popover] url in
            popover?.close()
            guard let self else { return }
            window?.makeFirstResponder(self)
            perform(.link(url: url), named: DocsFormat.link.name)
        }
        linkPopover = popover
        let anchor = convert(window!.convertFromScreen(firstRect(forCharacterRange: selectedRange(), actualRange: nil)), from: nil)
        popover.show(relativeTo: anchor, of: self, preferredEdge: .maxY)
        let field = controller.field
        controller.view.window?.makeFirstResponder(field)
        field.currentEditor()?.selectedRange = NSRange(location: field.stringValue.utf16.count, length: 0)
    }

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        drawQuoteBars()
        guard string.isEmpty else { return }
        let origin = NSPoint(x: textContainerInset.width + (textContainer?.lineFragmentPadding ?? 0), y: textContainerInset.height)
        NSAttributedString(string: DocsPane.placeholder, attributes: [.font: NSFont.systemFont(ofSize: 13), .foregroundColor: placeholderColor])
            .draw(at: origin)
    }

    /// A 2 pt bar at each quote line's leading edge, beside its 12 pt indent.
    private func drawQuoteBars() {
        guard let layout = layoutManager, let length = textStorage?.length else { return }
        quoteBarColor.setFill()
        for line in quoteLines where NSMaxRange(line) <= length {
            layout.enumerateLineFragments(forGlyphRange: layout.glyphRange(forCharacterRange: line, actualCharacterRange: nil)) { rect, _, container, _, _ in
                NSRect(x: self.textContainerOrigin.x + container.lineFragmentPadding, y: self.textContainerOrigin.y + rect.minY, width: 2, height: rect.height).fill()
            }
        }
    }

    override func mouseDown(with event: NSEvent) {
        defer { endClick() }
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

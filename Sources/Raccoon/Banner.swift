import AppKit
import RaccoonDomain

/// What a banner says (design-system §6 Banners): a glyph, a bold lead sentence, detail in
/// `textSecondary`, and trailing buttons.
struct Banner: Equatable {
    enum Glyph { case warning, error }

    /// Detail text; a path is `code`, set in SF Mono.
    enum Run: Equatable {
        case text(String)
        case code(String)
    }

    struct Button: Equatable {
        var title: String
        var isPrimary: Bool
    }

    var glyph: Glyph
    var lead: String
    var detail: [Run]
    var buttons: [Button]
}

/// surfaces.md §7: in over 200 ms, out over 150 ms, height and opacity; under Reduce Motion
/// only the opacity, over 150 ms.
nonisolated struct BannerMotion: Equatable {
    let duration: Double
    let animatesHeight: Bool

    init(appearing: Bool, reduceMotion: Bool) {
        duration = appearing && !reduceMotion ? 0.2 : 0.15
        animatesHeight = !reduceMotion
    }
}

/// The window banner for a Data Folder that cannot be used. nil when there is nothing wrong.
enum DataFolderBanner {
    static func content(for error: StoreError?) -> Banner? {
        let (lead, problem, path): (String, String, String)
        switch error {
        case nil:
            return nil
        case .unwritable(let p, _):
            (lead, problem, path) = ("Raccoon can't write to the Data Folder.", " is read-only.", p)
        case .unreadable(let p, let reason), .undecodable(let p, let reason):
            (lead, problem, path) = ("Raccoon can't read the Data Folder.", " can't be read: \(reason)", p)
        }
        return Banner(
            glyph: .error, lead: lead,
            detail: [.text(" "), .code((path as NSString).abbreviatingWithTildeInPath),
                     .text(problem + " Collections are unavailable; Drafts and sending still work.")],
            buttons: [Banner.Button(title: "Choose Folder…", isPrimary: true)]
        )
    }
}

/// One banner: 36 pt minimum, growing with its text. The host pins it with `height`, which
/// show and hide animate; hidden, it takes no height.
final class BannerView: NSView {
    let glyph = NSImageView()
    let text = NSTextField(wrappingLabelWithString: "")
    private(set) var buttons: [NSButton] = []
    /// Activated by the host that lays the banner out.
    private(set) lazy var height = heightAnchor.constraint(equalToConstant: 0)
    var onButton: ((Int) -> Void)?

    private let theme: ThemeEnvironment
    private let reduceMotion: () -> Bool
    private let rule = CALayer()
    private(set) var content: Banner?

    init(theme: ThemeEnvironment, reduceMotion: @escaping () -> Bool) {
        self.theme = theme
        self.reduceMotion = reduceMotion
        super.init(frame: .zero)
        wantsLayer = true
        layer?.addSublayer(rule)
        isHidden = true
        text.isSelectable = false
        text.setAccessibilityRole(.staticText)
        setAccessibilityRole(.group)
        addSubview(glyph)
        addSubview(text)
        theme.paint(self) { view, _ in view.render() }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func show(_ content: Banner, animated: Bool) {
        let appearing = isHidden
        if content != self.content {
            self.content = content
            buttons.forEach { $0.removeFromSuperview() }
            buttons = content.buttons.enumerated().map { index, _ in
                let button = NSButton(title: "", target: self, action: #selector(press))
                button.tag = index
                button.isBordered = false
                button.wantsLayer = true
                button.layer?.cornerRadius = 6
                button.layer?.borderWidth = 1
                addSubview(button)
                return button
            }
            render()
            needsLayout = true
        }
        isHidden = false
        let target = height(forWidth: layoutWidth)
        guard animated, appearing else {
            alphaValue = 1
            height.constant = target
            return
        }
        let motion = BannerMotion(appearing: true, reduceMotion: reduceMotion())
        alphaValue = 0
        height.constant = motion.animatesHeight ? 0 : target
        animate(motion) { view in
            view.animator().alphaValue = 1
            if motion.animatesHeight { view.height.animator().constant = target }
        }
    }

    func hide(animated: Bool) {
        guard !isHidden else { return }
        let finish: @MainActor @Sendable () -> Void = { [weak self] in
            guard let self, self.content == nil else { return }
            self.isHidden = true
            self.height.constant = 0
        }
        content = nil
        guard animated else { return finish() }
        let motion = BannerMotion(appearing: false, reduceMotion: reduceMotion())
        animate(motion, completion: finish) { view in
            view.animator().alphaValue = 0
            if motion.animatesHeight { view.height.animator().constant = 0 }
        }
    }

    private func animate(_ motion: BannerMotion, completion: (@MainActor @Sendable () -> Void)? = nil, _ changes: @escaping (BannerView) -> Void) {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = motion.duration
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.23, 1, 0.32, 1)
            context.allowsImplicitAnimation = true
            changes(self)
            superview?.layoutSubtreeIfNeeded()
        } completionHandler: {
            MainActor.assumeIsolated { completion?() }
        }
    }

    @objc private func press(_ sender: NSButton) {
        onButton?(sender.tag)
    }

    private var layoutWidth: CGFloat { bounds.width > 0 ? bounds.width : superview?.bounds.width ?? 0 }

    /// The height its text needs at `width`, at least 36 pt; 0 while hidden.
    func height(forWidth width: CGFloat) -> CGFloat {
        guard !isHidden else { return 0 }
        return max(36, textHeight(width: textWidth(in: width)) + 12)
    }

    private static let side: CGFloat = 12
    private static let gap: CGFloat = 8
    private static let textX = side + 16 + gap

    private func buttonWidth(_ button: NSButton) -> CGFloat {
        (button.attributedTitle.size().width + 20).rounded(.up)
    }

    private func textWidth(in width: CGFloat) -> CGFloat {
        let buttonsWidth = buttons.reduce(0) { $0 + buttonWidth($1) + Self.gap }
        return max(0, width - Self.side - buttonsWidth - Self.textX)
    }

    private func textHeight(width: CGFloat) -> CGFloat {
        (text.cell?.cellSize(forBounds: NSRect(x: 0, y: 0, width: width, height: .greatestFiniteMagnitude)).height ?? 0).rounded(.up)
    }

    override func layout() {
        super.layout()
        rule.frame = NSRect(x: 0, y: 0, width: bounds.width, height: 1)
        let middle = bounds.height / 2
        glyph.frame = NSRect(x: Self.side, y: (middle - 8).rounded(), width: 16, height: 16)
        var x = bounds.width - Self.side
        for button in buttons.reversed() {
            let width = buttonWidth(button)
            x -= width
            button.frame = NSRect(x: x, y: (middle - 12).rounded(), width: width, height: 24)
            x -= Self.gap
        }
        let width = textWidth(in: bounds.width)
        let textHeight = textHeight(width: width)
        text.frame = NSRect(x: Self.textX, y: (middle - textHeight / 2).rounded(), width: width, height: textHeight)
        // The window was resized: the text may wrap differently.
        if !isHidden, content != nil, height.isActive, height.constant != height(forWidth: bounds.width) {
            height.constant = height(forWidth: bounds.width)
        }
    }

    /// Every colour, read now: runs again on each Flavor change through `paint`.
    private func render() {
        layer?.backgroundColor = theme.color(.backgroundElevated).cgColor
        rule.backgroundColor = theme.color(.border).cgColor
        guard let content else { return }
        let (symbol, token): (String, ColorToken) = switch content.glyph {
        case .warning: ("exclamationmark.triangle", .warning)
        case .error: ("exclamationmark.circle", .error)
        }
        glyph.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 13, weight: .regular))
        glyph.contentTintColor = theme.color(token)

        let line = NSMutableAttributedString(string: content.lead, attributes: [
            .font: NSFont.systemFont(ofSize: 13, weight: .semibold), .foregroundColor: theme.color(.text),
        ])
        for run in content.detail {
            let (string, font): (String, NSFont) = switch run {
            case .text(let string): (string, .systemFont(ofSize: 13))
            case .code(let string): (string, .monospacedSystemFont(ofSize: 12, weight: .regular))
            }
            line.append(NSAttributedString(string: string, attributes: [.font: font, .foregroundColor: theme.color(.textSecondary)]))
        }
        text.attributedStringValue = line

        for (button, model) in zip(buttons, content.buttons) {
            let (fill, edge, ink) = model.isPrimary
                ? (ColorToken.accent, ColorToken.accent, ColorToken.textOnAccent)
                : (.background, .border, .text)
            button.attributedTitle = NSAttributedString(string: model.title, attributes: [
                .font: NSFont.systemFont(ofSize: 12, weight: model.isPrimary ? .semibold : .regular), .foregroundColor: theme.color(ink),
            ])
            button.layer?.backgroundColor = theme.color(fill).cgColor
            button.layer?.borderColor = theme.color(edge).cgColor
        }
    }
}

/// Keeps the window banner on the Data Folder's state, and runs Choose Folder…. A folder
/// that fails to load keeps the banner up; Cancel in the panel changes nothing.
final class DataFolderBannerBinding {
    private let window: WindowModel
    private let banner: BannerView
    private let chooseFolder: () async -> String?

    /// `chooseFolder` is the open panel in the app, returning nil on Cancel.
    init(window: WindowModel, banner: BannerView, chooseFolder: @escaping () async -> String?) {
        self.window = window
        self.banner = banner
        self.chooseFolder = chooseFolder
        banner.onButton = { [weak self] _ in self?.choose() }
        update()
    }

    private func update() {
        let content = withObservationTracking { DataFolderBanner.content(for: window.dataFolderError) } onChange: { [weak self] in
            Task { @MainActor in self?.update() }
        }
        // Not yet in a window: nothing to animate from.
        let animated = banner.window != nil
        if let content { banner.show(content, animated: animated) } else { banner.hide(animated: animated) }
    }

    private func choose() {
        Task {
            guard let root = await chooseFolder() else { return }
            await window.chooseDataFolder(root)
        }
    }
}

/// The Tab banners (design-system §6 Banners): a notice first, else Changed on Disk.
enum TabBanner {
    static let dismiss = Banner.Button(title: "Dismiss", isPrimary: false)

    /// `changedOnDisk` is the file's name while the Tab is Changed on Disk.
    static func content(notice: TabNotice?, changedOnDisk: String?) -> Banner? {
        switch (notice, changedOnDisk) {
        case (.notSaved(let file, let reason)?, _):
            Banner(glyph: .error, lead: "Not saved.",
                   detail: [.text(" Couldn't write \(file): \(reason). The Tab keeps your edits.")], buttons: [dismiss])
        case (.deletedOnDisk(let file)?, _):
            Banner(glyph: .warning, lead: "Deleted on disk.",
                   detail: [.text(" \(file) is gone. This Tab is now a Draft with your content, and ⌘S saves it again.")], buttons: [dismiss])
        case (nil, let file?):
            Banner(glyph: .warning, lead: "Changed on Disk.",
                   detail: [.text(" \(file) was changed outside Raccoon. Your edits are kept until you choose.")],
                   buttons: [Banner.Button(title: "Keep Mine", isPrimary: false), Banner.Button(title: "Reload", isPrimary: true)])
        case (nil, nil):
            nil
        }
    }
}

/// The one Tab banner under the tab strip, showing the selected Tab's.
final class TabBannerBinding {
    let view: BannerView
    private let window: WindowModel

    init(window: WindowModel, theme: ThemeEnvironment, reduceMotion: @escaping () -> Bool) {
        self.window = window
        view = BannerView(theme: theme, reduceMotion: reduceMotion)
        view.onButton = { [weak self] index in self?.press(index) }
        update()
    }

    private func update() {
        let content = withObservationTracking { () -> Banner? in
            guard let tab = window.selectedTab else { return nil }
            return TabBanner.content(notice: tab.notice, changedOnDisk: tab.tab.isChangedOnDisk ? window.fileName(of: tab.tab) : nil)
        } onChange: { [weak self] in
            Task { @MainActor in self?.update() }
        }
        // Switching Tabs swaps the banner at once; only a change on the shown Tab animates.
        let animated = view.window != nil
        if let content { view.show(content, animated: animated) } else { view.hide(animated: animated) }
    }

    private func press(_ index: Int) {
        guard let tab = window.selectedTab else { return }
        if tab.notice != nil {
            tab.notice = nil
            update()
        }
    }
}

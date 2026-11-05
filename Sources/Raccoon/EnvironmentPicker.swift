import AppKit
import Observation

/// The toolbar pop-up (design-system §6 Environment picker): No Environment, each Environment,
/// the active one checked, and Edit Environments…. It shows the window's choice and reports
/// picks; the window decides.
final class EnvironmentPicker: DropdownPopUp {
    private var onPick: (String?) -> Void = { _ in }
    /// Edit Environments…, which opens the Environments sheet.
    var onEdit: () -> Void = {}

    /// A borderless pop-up draws the plain up/down chevrons the Workspace pop-up has, not the
    /// bezel's blue capsule; its fill and 8 pt text inset are drawn here.
    override class var cellClass: AnyClass? {
        get { InsetPopUpCell.self }
        set {}
    }

    /// Leading inset, gap between the title and the chevrons, and the chevrons with their trailing inset.
    private static let lead: CGFloat = 8, gap: CGFloat = 8, chevrons: CGFloat = 18

    private final class InsetPopUpCell: NSPopUpButtonCell {
        override func titleRect(forBounds rect: NSRect) -> NSRect {
            var title = super.titleRect(forBounds: rect)
            title.origin.x = EnvironmentPicker.lead
            title.size.width = rect.width - EnvironmentPicker.lead - EnvironmentPicker.gap - EnvironmentPicker.chevrons
            return title
        }
    }

    /// The toolbar fixes this view's size once, so the width is set here from the selected title
    /// each time it changes, to a 200 pt maximum.
    private lazy var widthConstraint = widthAnchor.constraint(equalToConstant: 200)
    private func fitWidth() {
        let text = (titleOfSelectedItem ?? "").size(withAttributes: [.font: font ?? .systemFont(ofSize: 12)]).width
        widthConstraint.constant = min(200, ceil(text) + 2 + Self.lead + Self.gap + Self.chevrons)
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        effectiveAppearance.performAsCurrentDrawingAppearance { layer?.backgroundColor = NSColor.quaternaryLabelColor.cgColor }
    }

    init() {
        super.init(frame: .zero, pullsDown: false)
        isBordered = false
        wantsLayer = true
        layer?.cornerRadius = 6
        layer?.backgroundColor = NSColor.quaternaryLabelColor.cgColor
        font = .systemFont(ofSize: 12)
        setAccessibilityLabel("Environment")
        // Long names end-truncate at 200 pt; the menu shows them in full.
        (cell as? NSPopUpButtonCell)?.lineBreakMode = .byTruncatingTail
        translatesAutoresizingMaskIntoConstraints = false
        heightAnchor.constraint(equalToConstant: 28).isActive = true
        widthConstraint.isActive = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// Follows the window's Environments and Active Environment for as long as both live.
    func bind(_ window: WindowModel) {
        onPick = { [weak window] in window?.pickActiveEnvironment($0) }
        render(window)
    }

    private func render(_ window: WindowModel) {
        withObservationTracking {
            reload(names: window.environments.map(\.name), active: window.activeEnvironment)
        } onChange: { [weak self, weak window] in
            Task { @MainActor in if let window { self?.render(window) } }
        }
    }

    /// The item showing the Active Environment, which Edit Environments… must not replace.
    private var chosen = 0

    /// An active name whose file is gone shows No Environment (surfaces.md §5).
    private func reload(names: [String], active: String?) {
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.addItem(item("No Environment", name: nil))
        menu.addItem(.separator())
        names.forEach { menu.addItem(item($0, name: $0)) }
        menu.addItem(.separator())
        let edit = NSMenuItem(title: "Edit Environments…", action: #selector(edit(_:)), keyEquivalent: "")
        edit.target = self
        menu.addItem(edit)
        self.menu = menu
        chosen = names.firstIndex { $0 == active }.map { $0 + 2 } ?? 0
        selectItem(at: chosen)
        fitWidth()
    }

    private func item(_ title: String, name: String?) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: #selector(pick(_:)), keyEquivalent: "")
        item.representedObject = name
        item.target = self
        return item
    }

    @objc func pick(_ item: NSMenuItem) { onPick(item.representedObject as? String) }

    /// An action, not a choice: the pop-up goes on showing the Active Environment.
    @objc func edit(_ item: NSMenuItem) {
        selectItem(at: chosen)
        onEdit()
    }
}

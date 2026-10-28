import AppKit
import Observation

/// The toolbar pop-up (design-system §6 Environment picker): No Environment, each Environment,
/// the active one checked, and Edit Environments…. It shows the window's choice and reports
/// picks; the window decides.
final class EnvironmentPicker: NSPopUpButton {
    private var onPick: (String?) -> Void = { _ in }
    /// Edit Environments…, which opens the Environments sheet.
    var onEdit: () -> Void = {}

    init() {
        super.init(frame: .zero, pullsDown: false)
        // 28 pt high with the text centered (design-system §6 Environment picker).
        controlSize = .large
        font = .systemFont(ofSize: 12)
        setAccessibilityLabel("Environment")
        // Long names end-truncate at 200 pt; the menu shows them in full.
        (cell as? NSPopUpButtonCell)?.lineBreakMode = .byTruncatingTail
        translatesAutoresizingMaskIntoConstraints = false
        widthAnchor.constraint(lessThanOrEqualToConstant: 200).isActive = true
        setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
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
        invalidateIntrinsicContentSize()
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

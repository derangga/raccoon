import AppKit
import Observation

/// The toolbar Dropdown (design-system §6 Environment picker): No Environment, each Environment,
/// the active one chosen, and Edit Environments…. It shows the window's choice and reports
/// picks; the window decides.
final class EnvironmentPicker: Dropdown {
    /// Edit Environments…, which opens the Environments sheet.
    var onEdit: () -> Void = {}
    private var onChoose: (String?) -> Void = { _ in }

    /// The toolbar fixes this view's size once, so the width is set here from the title each
    /// time it changes, to a 200 pt maximum.
    private lazy var widthConstraint = widthAnchor.constraint(equalToConstant: 200)

    init(theme: ThemeEnvironment) {
        super.init(label: "Environment", theme: theme, height: 28)
        maxWidth = 200
        widthConstraint.isActive = true
        onPick = { [unowned self] pick in
            switch pick {
            case .option("none"): onChoose(nil)
            case let .option(id): onChoose(String(id.dropFirst("env:".count)))
            case .action: onEdit()
            }
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// Follows the window's Environments and Active Environment for as long as both live.
    func bind(_ window: WindowModel) {
        onChoose = { [weak window] in window?.pickActiveEnvironment($0) }
        render(window)
    }

    private func render(_ window: WindowModel) {
        withObservationTracking {
            reload(names: window.environments.map(\.name), active: window.activeEnvironment)
        } onChange: { [weak self, weak window] in
            Task { @MainActor in if let window { self?.render(window) } }
        }
    }

    /// An active name whose file is gone shows No Environment (surfaces.md §5).
    private func reload(names: [String], active: String?) {
        let active = names.contains { $0 == active } ? active : nil
        entries = [.option(id: "none", title: "No Environment", detail: nil, isChosen: active == nil), .separator]
            + names.map { .option(id: "env:" + $0, title: $0, detail: nil, isChosen: $0 == active) }
            + [.separator, .action(id: "edit", title: "Edit Environments…")]
        widthConstraint.constant = fittingWidth
    }
}

import AppKit
import RaccoonDomain

/// The Dropdown at the top of the sidebar (design-system §6 Workspace pop-up): the open
/// Workspace's title, and a list of every Workspace, New Workspace…, Open Workspace… and Manage
/// Workspaces…. It only shows and reports; the window decides.
final class WorkspacePopUp: Dropdown {
    var onSwitch: (String) -> Void = { _ in }
    var onNew: () -> Void = {}
    var onOpen: () -> Void = {}
    var onManage: () -> Void = {}

    init(theme: ThemeEnvironment) {
        super.init(label: "Workspace", theme: theme, height: 24)
        onPick = { [unowned self] pick in
            switch pick {
            case let .option(path): onSwitch(path)
            case .action("new"): onNew()
            case .action("open"): onOpen()
            case .action("manage"): onManage()
            case .action: break
            }
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// Rebuilt whenever the list or the open Workspace changes. The open one is chosen, so the
    /// title stays on it whichever row was picked last.
    func reload(workspaces: [String], open: String) {
        entries = WorkspaceList.titles(workspaces).map {
            .option(id: $0.path, title: $0.title, detail: ($0.path as NSString).abbreviatingWithTildeInPath, isChosen: $0.path == open)
        } + [
            .separator,
            .action(id: "new", title: "New Workspace…"),
            .action(id: "open", title: "Open Workspace…"),
            .action(id: "manage", title: "Manage Workspaces…"),
        ]
    }
}

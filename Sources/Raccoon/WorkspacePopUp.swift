import AppKit
import RaccoonDomain

/// The borderless pop-up at the top of the sidebar (design-system §6 Workspace pop-up): the open
/// Workspace's title, and a menu of every Workspace, New Workspace…, Open Workspace… and Manage
/// Workspaces…. It only shows and reports; the window decides.
final class WorkspacePopUp: DropdownPopUp {
    var onSwitch: (String) -> Void = { _ in }
    var onNew: () -> Void = {}
    var onOpen: () -> Void = {}
    var onManage: () -> Void = {}

    private var openIndex = 0

    init() {
        super.init(frame: .zero, pullsDown: false)
        isBordered = false
        controlSize = .small
        font = .systemFont(ofSize: 12)
        setAccessibilityLabel("Workspace")
        (cell as? NSPopUpButtonCell)?.lineBreakMode = .byTruncatingTail
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// Rebuilt whenever the list or the open Workspace changes. The open one is selected, so the
    /// title stays on it however the last item was chosen.
    func reload(workspaces: [String], open: String) {
        let menu = NSMenu()
        let titles = WorkspaceList.titles(workspaces)
        for row in titles {
            menu.addItem(item(row, action: #selector(switchTo(_:))))
        }
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "New Workspace…", action: #selector(newWorkspace), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Open Workspace…", action: #selector(openWorkspace), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Manage Workspaces…", action: #selector(manageWorkspaces), keyEquivalent: ""))
        menu.items.forEach { $0.target = self }
        menu.autoenablesItems = false
        self.menu = menu
        openIndex = titles.firstIndex { $0.path == open } ?? 0
        selectItem(at: openIndex)
    }

    private func item(_ row: WorkspaceTitle, action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: row.title, action: action, keyEquivalent: "")
        item.representedObject = row.path
        item.toolTip = (row.path as NSString).abbreviatingWithTildeInPath
        item.target = self
        return item
    }

    /// The action ran: the pop-up goes back to the open Workspace until the window reloads it.
    private func reselect(_ action: () -> Void) {
        action()
        selectItem(at: openIndex)
    }

    @objc private func switchTo(_ sender: NSMenuItem) { reselect { onSwitch(sender.representedObject as? String ?? "") } }
    @objc private func newWorkspace() { reselect(onNew) }
    @objc private func openWorkspace() { reselect(onOpen) }
    @objc private func manageWorkspaces() { reselect(onManage) }
}

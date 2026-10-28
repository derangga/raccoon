import AppKit
import Observation
import RaccoonDomain
import UniformTypeIdentifiers

@main
enum RaccoonApp {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.regular)
        app.run()
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var windowModel: WindowModel?
    private var windowController: MainWindowController?
    private var tabController: TabViewController?
    private var content: ContentViewController?
    private var themeController: ThemeController?
    private var closer: TabCloser?
    private var saver: DraftSaver?
    private var sidebar: SidebarViewController?
    private var dataFolderBanner: DataFolderBannerBinding?
    /// Reads the files picked for Postman Import.
    private let files = CompositionRoot.fileReading()
    /// The app's preference, never a Session's (tabs.md §close).
    private let closeMemory = CompositionRoot.closeMemory(defaults: .standard)

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Raccoon's Tabs are its own; system window tabs would add a second kind on ⌘T's menu.
        NSWindow.allowsAutomaticWindowTabbing = false
        let windowModel = CompositionRoot.live(defaults: .standard)
        // Loading restores the Session too: a Request Tab is looked up in the index first.
        windowModel.loadDataFolder()
        self.windowModel = windowModel
        let themeController = ThemeController(defaults: .standard, catalog: ThemeCatalog.load(), appearanceSource: NSApp)
        self.themeController = themeController
        NSApp.mainMenu = MainMenu.make(theme: themeController)
        let theme = themeController.theme
        // The inspector's state is UserDefaults' (Q14), never the Session's.
        let inspectorMemory = CompositionRoot.inspectorMemory(defaults: .standard)
        let windowController = MainWindowController(theme: theme, inspector: inspectorMemory, reduceMotion: { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion })
        let chooseWorkspaceFolder = { [weak windowController] () async -> String? in
            guard let window = windowController?.window else { return nil }
            let panel = NSOpenPanel()
            panel.canChooseDirectories = true
            panel.canChooseFiles = false
            panel.canCreateDirectories = true
            panel.prompt = "Open"
            return await panel.beginSheetModal(for: window) == .OK ? panel.url?.path : nil
        }
        dataFolderBanner = DataFolderBannerBinding(window: windowModel, banner: windowController.banner, chooseFolder: chooseWorkspaceFolder)
        // A Session of zero Tabs opens on the empty state: the editor holds a Tab no list has.
        let tabController = TabViewController(model: windowModel.tabs.first ?? windowModel.unlistedTab(), theme: theme)
        let strip = TabStripView(window: windowModel, theme: theme)
        let saver = DraftSaver(window: windowModel, ask: { [weak windowController] locations, location, reply in
            guard let window = windowController?.window else { return reply(nil) }
            // A turn later: from the close prompt, its own sheet is still ending.
            Task { @MainActor in SaveDraftSheet.present(on: window, locations: locations, default: location, reply: reply) }
        }, focusURL: { [weak tabController] in
            guard let tabController else { return }
            tabController.view.window?.makeFirstResponder(tabController.urlBar.urlField)
        })
        self.saver = saver
        let closer = TabCloser(window: windowModel, saver: saver, memory: closeMemory, confirmForce: { [weak windowController] losing, reply in
            guard let window = windowController?.window else { return }
            ForceCloseConfirm.ask(losing: losing, in: window, reply: reply)
        }) { [weak windowController] model, reply in
            guard let window = windowController?.window else { return }
            // A turn later: from the previous Tab's question in a batch, its sheet is still ending.
            Task { @MainActor in CloseConfirm.ask(model, name: windowModel.name(of: model.tab), in: window, reply: reply) }
        }
        strip.onClose = { closer.close($0) }
        strip.onCloseMenu = { scope, model, force in closer.close(scope, of: model, force: force) }
        self.closer = closer
        let sidebar = SidebarViewController(window: windowModel, theme: theme) { path in
            NSWorkspace.shared.activateFileViewerSelecting([URL(filePath: path)])
        }
        sidebar.askName = { [weak windowController] title, name, button, reply in
            guard let window = windowController?.window else { return reply(nil) }
            NameSheet.present(on: window, title: title, name: name, button: button, reply: reply)
        }
        sidebar.chooseWorkspaceFolder = chooseWorkspaceFolder
        sidebar.chooseNewWorkspace = { [weak windowController] in
            guard let window = windowController?.window else { return nil }
            let panel = NSSavePanel()
            panel.prompt = "Create"
            panel.nameFieldLabel = "Name:"
            panel.canCreateDirectories = true
            panel.directoryURL = URL.homeDirectory
            return await panel.beginSheetModal(for: window) == .OK ? panel.url?.path : nil
        }
        sidebar.showError = { [weak windowController] message in
            guard let window = windowController?.window else { return }
            let alert = NSAlert()
            alert.messageText = message
            alert.beginSheetModal(for: window)
        }
        sidebar.importFromPostman = { [weak self] in self?.importFromPostman(nil) }
        sidebar.focusEditor = { [weak tabController] in
            tabController?.view.window?.makeFirstResponder(tabController?.urlBar.urlField)
        }
        windowController.environmentPicker.bind(windowModel)
        windowController.environmentPicker.onEdit = { [weak self] in self?.editEnvironments(nil) }
        windowController.split.showSidebar(sidebar)
        self.sidebar = sidebar
        let tabBanner = TabBannerBinding(window: windowModel, theme: theme, reduceMotion: { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion })
        // A click shows the sidebar and selects the row; focus stays where it is.
        let breadcrumb = BreadcrumbBinding(window: windowModel, theme: theme) { [weak windowController, weak sidebar] path in
            windowController?.split.revealSidebar()
            sidebar?.reveal(path: path)
        }
        let content = ContentViewController(strip: strip, breadcrumb: breadcrumb, tab: tabController, banner: tabBanner,
                                            emptyState: EmptyStateView(theme: theme, menu: NSApp.mainMenu))
        windowController.split.showTab(content)
        self.content = content
        self.tabController = tabController
        let inspector = InspectorViewController(window: windowModel, theme: theme, memory: inspectorMemory)
        inspector.onEditEnvironments = { [weak self] in self?.editEnvironments(nil) }
        windowController.split.showInspector(inspector)
        // "Variables in request" in the Variable popover.
        VariableTooltipPanel.shared.onReveal = { [weak windowController, weak inspector] name in
            windowController?.split.showInspector()
            inspector?.reveal(name)
        }
        showSelectedTab()
        windowController.showWindow(nil)
        self.windowController = windowController
        NSApp.activate()
    }

    /// ⌘Q, logout and restart all end here, with no prompt: the Session keeps every Tab.
    func applicationWillTerminate(_ notification: Notification) { windowModel?.quit() }

    /// The one editor follows the selection, however it changed; with no Tab, the empty state.
    private func showSelectedTab() {
        guard let windowModel, let tabController else { return }
        let selected = withObservationTracking { windowModel.selectedTab } onChange: { [weak self] in
            Task { @MainActor in self?.showSelectedTab() }
        }
        if let selected { tabController.bind(selected) }
        content?.showsTab(selected != nil)
    }

    @objc func newTab(_ sender: Any?) { windowModel?.newTab() }
    @objc func newCollection(_ sender: Any?) { sidebar?.newCollection(sender) }
    @objc func save(_ sender: Any?) { if let tab = windowModel?.selectedTab { saver?.save(tab) } }
    @objc func closeTab(_ sender: Any?) { if let tab = windowModel?.selectedTab { closer?.close(tab) } }
    @objc func forceCloseTab(_ sender: Any?) { if let tab = windowModel?.selectedTab { closer?.close(.tab, of: tab, force: true) } }
    /// File ▸ Always Discard Unsaved Changes: the way back from the close sheet's checkbox.
    @objc func toggleAlwaysDiscard(_ sender: Any?) { closeMemory.remember(!closeMemory.alwaysDiscards()) }
    @objc func showTab(_ sender: NSMenuItem) { windowModel?.select(number: sender.tag) }
    @objc func showNextTab(_ sender: Any?) { windowModel?.selectNext() }
    @objc func showPreviousTab(_ sender: Any?) { windowModel?.selectPrevious() }
    /// ⌃E opens the toolbar's Environment pop-up.
    @objc func chooseEnvironment(_ sender: Any?) { windowController?.environmentPicker.performClick(sender) }
    /// ⌥⌘F: opens a hidden sidebar and focuses its filter.
    @objc func focusFilter(_ sender: Any?) {
        windowController?.split.revealSidebar()
        sidebar?.focusFilter()
    }
    /// ⇧⌘I and the sidebar's + menu: an open panel for many .json files, then the Import sheet.
    /// Cancel in the panel opens no sheet.
    @objc func importFromPostman(_ sender: Any?) {
        guard let window = windowController?.window, window.attachedSheet == nil, let windowModel else { return }
        Task { @MainActor [weak self, files] in
            let panel = NSOpenPanel()
            panel.allowsMultipleSelection = true
            panel.allowedContentTypes = [.json]
            guard await panel.beginSheetModal(for: window) == .OK, !panel.urls.isEmpty else { return }
            // By file name, as Finder lists them: the rows and " 2" do not depend on click order.
            let paths = panel.urls.map(\.path).sorted { $0.localizedStandardCompare($1) == .orderedAscending }
            let picked = PickedFile.read(paths, from: files)
            PostmanImportSheet.present(on: window, files: picked, window: windowModel) { [weak self] collection in
                guard let collection else { return }
                self?.windowController?.split.revealSidebar()
                self?.sidebar?.select(path: collection)
            }
        }
    }

    /// ⌥⌃E and the picker's Edit Environments….
    @objc func editEnvironments(_ sender: Any?) {
        guard let window = windowController?.window, let windowModel, let theme = themeController?.theme else { return }
        EnvironmentsSheet.present(on: window, model: windowModel, theme: theme)
    }
}

extension AppDelegate: NSMenuItemValidation {
    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        switch item.action {
        case #selector(toggleAlwaysDiscard(_:)):
            item.state = closeMemory.alwaysDiscards() ? .on : .off
            return true
        // Disabled, not hidden, while no Tab is open (surfaces.md §5).
        case #selector(save(_:)), #selector(closeTab(_:)), #selector(forceCloseTab(_:)), #selector(showNextTab(_:)), #selector(showPreviousTab(_:)):
            return windowModel?.selectedTab != nil
        case #selector(showTab(_:)):
            return !(windowModel?.tabs.isEmpty ?? true)
        default:
            return true
        }
    }
}

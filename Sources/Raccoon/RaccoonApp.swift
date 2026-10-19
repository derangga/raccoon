import AppKit
import Observation

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
    private var themeController: ThemeController?
    private var closer: TabCloser?
    private var dataFolderBanner: DataFolderBannerBinding?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Raccoon's Tabs are its own; system window tabs would add a second kind on ⌘T's menu.
        NSWindow.allowsAutomaticWindowTabbing = false
        let windowModel = CompositionRoot.live(defaults: .standard)
        // Before relaunch: restoring a Request Tab looks its Request up in the index.
        windowModel.loadDataFolder()
        windowModel.relaunch()
        self.windowModel = windowModel
        let themeController = ThemeController(defaults: .standard, catalog: ThemeCatalog.load(), appearanceSource: NSApp)
        self.themeController = themeController
        NSApp.mainMenu = MainMenu.make(theme: themeController)
        let theme = themeController.theme
        let windowController = MainWindowController(theme: theme, reduceMotion: { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion })
        dataFolderBanner = DataFolderBannerBinding(window: windowModel, banner: windowController.banner) { [weak windowController] in
            guard let window = windowController?.window else { return nil }
            let panel = NSOpenPanel()
            panel.canChooseDirectories = true
            panel.canChooseFiles = false
            panel.canCreateDirectories = true
            panel.prompt = "Choose"
            return await panel.beginSheetModal(for: window) == .OK ? panel.url?.path : nil
        }
        let tabController = TabViewController(model: windowModel.tabs[0], theme: theme)
        let strip = TabStripView(window: windowModel, theme: theme)
        let closer = TabCloser(window: windowModel) { [weak windowController] model, reply in
            guard let window = windowController?.window else { return }
            CloseConfirm.ask(model, name: windowModel.name(of: model.tab), in: window, reply: reply)
        }
        strip.onClose = closer.close
        self.closer = closer
        windowController.split.showSidebar(SidebarViewController(window: windowModel, theme: theme) { path in
            NSWorkspace.shared.activateFileViewerSelecting([URL(filePath: path)])
        })
        windowController.split.showTab(ContentViewController(strip: strip, tab: tabController))
        self.tabController = tabController
        showSelectedTab()
        windowController.showWindow(nil)
        self.windowController = windowController
        NSApp.activate()
    }

    /// ⌘Q, logout and restart all end here, with no prompt: the Session keeps every Tab.
    func applicationWillTerminate(_ notification: Notification) { windowModel?.quit() }

    /// The one editor follows the selection, however it changed.
    private func showSelectedTab() {
        guard let windowModel, let tabController else { return }
        let selected = withObservationTracking { windowModel.selectedTab } onChange: { [weak self] in
            Task { @MainActor in self?.showSelectedTab() }
        }
        if let selected { tabController.bind(selected) }
    }

    @objc func newTab(_ sender: Any?) { windowModel?.newTab() }
    @objc func closeTab(_ sender: Any?) { if let tab = windowModel?.selectedTab { closer?.close(tab) } }
    @objc func showTab(_ sender: NSMenuItem) { windowModel?.select(number: sender.tag) }
    @objc func showNextTab(_ sender: Any?) { windowModel?.selectNext() }
    @objc func showPreviousTab(_ sender: Any?) { windowModel?.selectPrevious() }
}

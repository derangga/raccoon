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

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Raccoon's Tabs are its own; system window tabs would add a second kind on ⌘T's menu.
        NSWindow.allowsAutomaticWindowTabbing = false
        NSApp.mainMenu = MainMenu.make()
        let windowModel = CompositionRoot.live()
        self.windowModel = windowModel
        let isDark = NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        let theme = ThemeEnvironment(catalog: ThemeCatalog.load(), isDark: isDark)
        let windowController = MainWindowController(theme: theme)
        let tabController = TabViewController(model: windowModel.tabs[0], theme: theme)
        windowController.split.showTab(tabController)
        self.tabController = tabController
        showSelectedTab()
        windowController.showWindow(nil)
        self.windowController = windowController
        NSApp.activate()
    }

    /// The one editor follows the selection, however it changed.
    private func showSelectedTab() {
        guard let windowModel, let tabController else { return }
        let selected = withObservationTracking { windowModel.selectedTab } onChange: { [weak self] in
            Task { @MainActor in self?.showSelectedTab() }
        }
        if let selected { tabController.bind(selected) }
    }

    @objc func newTab(_ sender: Any?) { windowModel?.newTab() }
    @objc func showTab(_ sender: NSMenuItem) { windowModel?.select(number: sender.tag) }
    @objc func showNextTab(_ sender: Any?) { windowModel?.selectNext() }
    @objc func showPreviousTab(_ sender: Any?) { windowModel?.selectPrevious() }
}

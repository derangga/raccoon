import AppKit

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

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = MainMenu.make()
        let windowModel = CompositionRoot.live()
        self.windowModel = windowModel
        let isDark = NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        let theme = ThemeEnvironment(catalog: ThemeCatalog.load(), isDark: isDark)
        let windowController = MainWindowController(theme: theme)
        windowController.split.showTab(TabViewController(model: windowModel.tabs[0], theme: theme))
        windowController.showWindow(nil)
        self.windowController = windowController
        NSApp.activate()
    }
}

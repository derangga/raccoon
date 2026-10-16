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
        windowModel = CompositionRoot.live()
        let isDark = NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        let windowController = MainWindowController(theme: ThemeEnvironment(catalog: ThemeCatalog.load(), isDark: isDark))
        windowController.showWindow(nil)
        self.windowController = windowController
        NSApp.activate()
    }
}

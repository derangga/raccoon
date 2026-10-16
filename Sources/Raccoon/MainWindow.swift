import AppKit
import Observation
import RaccoonDomain

/// The one main window: native sidebar, themed content, themed inspector, unified toolbar.
final class MainWindowController: NSWindowController, NSToolbarDelegate {
    let split: MainSplitViewController
    let sidebarToggle = MainWindowController.toggle(symbol: "sidebar.left", label: "Show Sidebar", action: #selector(NSSplitViewController.toggleSidebar(_:)))
    let inspectorToggle = MainWindowController.toggle(symbol: "sidebar.right", label: "Show Inspector", action: #selector(NSSplitViewController.toggleInspector(_:)))
    private var observations: [NSKeyValueObservation] = []

    init(theme: ThemeEnvironment) {
        split = MainSplitViewController(theme: theme)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1200, height: 760),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                              backing: .buffered, defer: false)
        window.title = "Raccoon"
        window.contentViewController = split
        window.setContentSize(NSSize(width: 1200, height: 760))
        window.center()
        super.init(window: window)

        let toolbar = NSToolbar(identifier: "MainWindow")
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        window.toolbar = toolbar
        window.toolbarStyle = .unified

        sidebarToggle.target = split
        inspectorToggle.target = split
        observations = [Self.mirror(split.sidebarItem, on: sidebarToggle), Self.mirror(split.inspectorItem, on: inspectorToggle)]
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    private static func toggle(symbol: String, label: String, action: Selector) -> NSButton {
        let button = NSButton(image: NSImage(systemSymbolName: symbol, accessibilityDescription: label)!, target: nil, action: action)
        button.setButtonType(.pushOnPushOff)
        button.bezelStyle = .texturedRounded
        button.toolTip = label
        return button
    }

    /// Pressed exactly while the pane is open, however it was opened.
    private static func mirror(_ item: NSSplitViewItem, on button: NSButton) -> NSKeyValueObservation {
        item.observe(\.isCollapsed, options: [.initial, .new]) { item, _ in
            let isCollapsed = item.isCollapsed
            MainActor.assumeIsolated { button.state = isCollapsed ? .off : .on }
        }
    }

    private static let sidebarToggleID = NSToolbarItem.Identifier("sidebarToggle")
    private static let inspectorToggleID = NSToolbarItem.Identifier("inspectorToggle")

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [Self.sidebarToggleID, .sidebarTrackingSeparator, .flexibleSpace, .inspectorTrackingSeparator, .flexibleSpace, Self.inspectorToggleID]
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarDefaultItemIdentifiers(toolbar)
    }

    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier identifier: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        let button = switch identifier {
        case Self.sidebarToggleID: sidebarToggle
        case Self.inspectorToggleID: inspectorToggle
        default: nil as NSButton?
        }
        guard let button else { return nil }
        let item = NSToolbarItem(itemIdentifier: identifier)
        item.view = button
        item.label = button.toolTip ?? ""
        return item
    }
}

/// Sizes from design-system §4. The panes are placeholders that later features fill.
final class MainSplitViewController: NSSplitViewController {
    let sidebarItem: NSSplitViewItem
    let inspectorItem: NSSplitViewItem

    init(theme: ThemeEnvironment) {
        sidebarItem = NSSplitViewItem(sidebarWithViewController: Pane(width: 232))
        sidebarItem.minimumThickness = 180
        sidebarItem.maximumThickness = 360
        inspectorItem = NSSplitViewItem(inspectorWithViewController: Pane(width: 280, view: ThemedView(theme: theme, fill: .backgroundRecessed, leadingBorder: .border)))
        inspectorItem.minimumThickness = 240
        inspectorItem.maximumThickness = 400
        inspectorItem.isCollapsed = true
        super.init(nibName: nil, bundle: nil)
        addSplitViewItem(sidebarItem)
        addSplitViewItem(NSSplitViewItem(viewController: Pane(width: 600, view: ThemedView(theme: theme, fill: .background))))
        addSplitViewItem(inspectorItem)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }
}

/// An empty pane with a starting width; the split view keeps it within its item's limits.
private final class Pane: NSViewController {
    private let width: CGFloat
    private let content: NSView

    init(width: CGFloat, view: NSView = NSView()) {
        self.width = width
        content = view
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func loadView() {
        content.frame = NSRect(x: 0, y: 0, width: width, height: 600)
        view = content
    }
}

/// A view filled with a Theme token, repainted whenever the current Flavor changes.
final class ThemedView: NSView {
    private let theme: ThemeEnvironment
    private let fill: ColorToken
    private let leadingBorder: ColorToken?
    private let border = CALayer()

    init(theme: ThemeEnvironment, fill: ColorToken, leadingBorder: ColorToken? = nil) {
        self.theme = theme
        self.fill = fill
        self.leadingBorder = leadingBorder
        super.init(frame: .zero)
        wantsLayer = true
        if leadingBorder != nil { layer?.addSublayer(border) }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        withObservationTracking {
            layer?.backgroundColor = theme.color(fill).cgColor
            if let leadingBorder { border.backgroundColor = theme.color(leadingBorder).cgColor }
        } onChange: { [weak self] in
            Task { @MainActor in self?.needsDisplay = true }
        }
    }

    override func layout() {
        super.layout()
        border.frame = NSRect(x: 0, y: 0, width: 1, height: bounds.height)
    }
}

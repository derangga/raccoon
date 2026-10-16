import AppKit
import Observation
import RaccoonDomain

/// The one main window: native sidebar, themed content, themed inspector, unified toolbar.
final class MainWindowController: NSWindowController, NSToolbarDelegate {
    let split: MainSplitViewController
    let sidebarToggle = MainWindowController.toggle(symbol: "sidebar.left", label: "Show Sidebar", action: #selector(NSSplitViewController.toggleSidebar(_:)))
    let inspectorToggle = MainWindowController.toggle(symbol: "sidebar.right", label: "Show Inspector", action: #selector(NSSplitViewController.toggleInspector(_:)))

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
        window.contentMinSize = NSSize(width: 760, height: 480)
        // Pressed exactly while the pane is open, docked or overlaid, however it was opened.
        split.onShownChange = { [sidebarToggle, inspectorToggle, split] in
            sidebarToggle.state = split.isSidebarShown ? .on : .off
            inspectorToggle.state = split.isInspectorShown ? .on : .off
        }
        split.onShownChange?()
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

/// Sizes from design-system §4, narrow layouts from Open UI Q2. The panes are placeholders
/// that later features fill.
///
/// Below 960 pt the sidebar collapses and opens as an overlay; the inspector docks while the
/// editor keeps 480 pt and overlays the content's trailing edge when it would not. Docked panes
/// show and hide by the unmodified NSSplitViewItem collapse.
final class MainSplitViewController: NSSplitViewController {
    let sidebarItem: NSSplitViewItem
    let inspectorItem: NSSplitViewItem
    private let sidebarPane = Pane(width: 232)
    private let contentPane: Pane
    private let inspectorPane: Pane

    /// Open, docked or overlaid. The toolbar toggles mirror these through onShownChange.
    private(set) var isSidebarShown = true { didSet { onShownChange?() } }
    private(set) var isInspectorShown = false { didSet { onShownChange?() } }
    var onShownChange: (() -> Void)?

    private var isNarrow = false
    private var sidebarWasDocked = true
    private var sidebarWidth: CGFloat = 232
    private var inspectorWidth: CGFloat = 280
    private var sidebarOverlay: Overlay?
    private var inspectorOverlay: Overlay?
    private var eventMonitor: Any?
    private var sidebarObservation: NSKeyValueObservation?

    var isSidebarOverlaid: Bool { sidebarOverlay != nil }
    var isInspectorOverlaid: Bool { inspectorOverlay != nil }

    init(theme: ThemeEnvironment) {
        contentPane = Pane(width: 600, view: ThemedView(theme: theme, fill: .background))
        inspectorPane = Pane(width: 280, view: ThemedView(theme: theme, fill: .backgroundRecessed, leadingBorder: .border))
        sidebarItem = NSSplitViewItem(sidebarWithViewController: sidebarPane)
        sidebarItem.minimumThickness = 180
        sidebarItem.maximumThickness = 360
        inspectorItem = NSSplitViewItem(inspectorWithViewController: inspectorPane)
        inspectorItem.minimumThickness = 240
        inspectorItem.maximumThickness = 400
        inspectorItem.isCollapsed = true
        super.init(nibName: nil, bundle: nil)
        addSplitViewItem(sidebarItem)
        addSplitViewItem(NSSplitViewItem(viewController: contentPane))
        addSplitViewItem(inspectorItem)
        // A docked sidebar can also be collapsed by dragging its divider.
        sidebarObservation = sidebarItem.observe(\.isCollapsed, options: [.new]) { [weak self] item, _ in
            let isCollapsed = item.isCollapsed
            MainActor.assumeIsolated {
                guard let self, !self.isNarrow else { return }
                self.isSidebarShown = !isCollapsed
            }
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func toggleSidebar(_ sender: Any?) {
        guard isNarrow else { return super.toggleSidebar(sender) }
        if isSidebarOverlaid { closeSidebarOverlay() } else { openSidebarOverlay() }
    }

    override func toggleInspector(_ sender: Any?) {
        isInspectorShown.toggle()
        placeInspector()
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        if !sidebarItem.isCollapsed, sidebarPane.view.frame.width > 0 { sidebarWidth = sidebarPane.view.frame.width }
        if !inspectorItem.isCollapsed, inspectorPane.view.frame.width > 0 { inspectorWidth = inspectorPane.view.frame.width }

        let isNarrow = view.bounds.width < 960
        if isNarrow != self.isNarrow {
            if isNarrow {
                sidebarWasDocked = !sidebarItem.isCollapsed
                self.isNarrow = true
                sidebarItem.isCollapsed = true
                isSidebarShown = false
            } else {
                closeSidebarOverlay()
                self.isNarrow = false
                sidebarItem.isCollapsed = !sidebarWasDocked
                isSidebarShown = sidebarWasDocked
            }
        }
        placeInspector()
        sidebarOverlay?.place(in: contentPane.view, leading: true)
        inspectorOverlay?.place(in: contentPane.view, leading: false)
    }

    /// Docked when the editor keeps 480 pt beside it, overlaid when it would not.
    private func placeInspector() {
        let divider = splitView.dividerThickness
        let sidebar = sidebarItem.isCollapsed ? 0 : sidebarWidth + divider
        let fits = view.bounds.width - sidebar - inspectorWidth - divider >= 480
        let docked = isInspectorShown && fits
        if inspectorItem.isCollapsed == docked {
            let item = view.window?.isVisible == true ? inspectorItem.animator() : inspectorItem
            item.isCollapsed = !docked
        }
        switch (isInspectorShown && !fits, inspectorOverlay) {
        case (true, nil):
            inspectorOverlay = Overlay(lending: inspectorPane, width: inspectorWidth, material: false)
            inspectorOverlay?.place(in: contentPane.view, leading: false)
            updateEventMonitor()
        case (false, let overlay?):
            overlay.close()
            inspectorOverlay = nil
            updateEventMonitor()
        default:
            break
        }
    }

    private func openSidebarOverlay() {
        sidebarOverlay = Overlay(lending: sidebarPane, width: sidebarWidth, material: true)
        sidebarOverlay?.place(in: contentPane.view, leading: true)
        isSidebarShown = true
        updateEventMonitor()
    }

    private func closeSidebarOverlay() {
        guard let overlay = sidebarOverlay else { return }
        overlay.close()
        sidebarOverlay = nil
        isSidebarShown = !isNarrow && !sidebarItem.isCollapsed
        updateEventMonitor()
    }

    private func closeOverlays() {
        closeSidebarOverlay()
        if isInspectorOverlaid {
            isInspectorShown = false
            placeInspector()
        }
    }

    private func updateEventMonitor() {
        let wanted = isSidebarOverlaid || isInspectorOverlaid
        if wanted, eventMonitor == nil {
            eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .leftMouseDown]) { [weak self] event in
                let (isEsc, isClick) = (event.type == .keyDown && event.keyCode == 53, event.type == .leftMouseDown)
                let (location, windowNumber) = (event.locationInWindow, event.windowNumber)
                let consume = MainActor.assumeIsolated {
                    self?.closesOverlays(isEsc: isEsc, isClick: isClick, location: location, windowNumber: windowNumber) ?? false
                }
                return consume ? nil : event
            }
        } else if !wanted, let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
    }

    /// Esc, or a click in the content outside every overlay, closes the overlays. Esc is
    /// consumed; a click still reaches the content. Clicks in the toolbar are left alone so
    /// the toggles keep working.
    func handleOverlayEvent(_ event: NSEvent) -> NSEvent? {
        let (isEsc, isClick) = (event.type == .keyDown && event.keyCode == 53, event.type == .leftMouseDown)
        return closesOverlays(isEsc: isEsc, isClick: isClick, location: event.locationInWindow, windowNumber: event.windowNumber) ? nil : event
    }

    /// Whether the event is consumed: only Esc is.
    private func closesOverlays(isEsc: Bool, isClick: Bool, location: NSPoint, windowNumber: Int) -> Bool {
        guard let window = view.window, windowNumber == window.windowNumber else { return false }
        if isEsc {
            closeOverlays()
            return true
        }
        let overlays = [sidebarOverlay, inspectorOverlay].compactMap { $0 }
        if isClick, window.contentLayoutRect.contains(location), !overlays.contains(where: { $0.frameInWindow.contains(location) }) {
            closeOverlays()
        }
        return false
    }
}

/// A pane's content shown over the content area's edge, with a shadow. It borrows the pane's
/// view while open and hands it back on close.
private final class Overlay {
    private let host: NSView
    private let pane: Pane
    private let width: CGFloat

    init(lending pane: Pane, width: CGFloat, material: Bool) {
        self.pane = pane
        self.width = width
        if material {
            let effect = NSVisualEffectView()
            effect.material = .sidebar
            effect.blendingMode = .withinWindow
            host = effect
        } else {
            host = NSView()
        }
        let shadow = NSShadow()
        shadow.shadowBlurRadius = 12
        shadow.shadowColor = .shadowColor.withAlphaComponent(0.3)
        host.shadow = shadow
        let content = pane.lend()
        content.frame = NSRect(x: 0, y: 0, width: width, height: 0)
        content.autoresizingMask = [.width, .height]
        host.addSubview(content)
    }

    var frameInWindow: NSRect { host.convert(host.bounds, to: nil) }

    func place(in container: NSView, leading: Bool) {
        if host.superview !== container { container.addSubview(host, positioned: .above, relativeTo: nil) }
        host.frame = NSRect(x: leading ? 0 : container.bounds.width - width, y: 0, width: width, height: container.bounds.height)
        host.subviews.first?.frame = host.bounds
    }

    func close() {
        host.removeFromSuperview()
        pane.takeBack()
    }
}

/// A pane whose content view can be lent to an overlay and taken back.
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
        view = NSView(frame: NSRect(x: 0, y: 0, width: width, height: 600))
        takeBack()
    }

    func lend() -> NSView {
        content.removeFromSuperview()
        return content
    }

    func takeBack() {
        content.frame = view.bounds
        content.autoresizingMask = [.width, .height]
        view.addSubview(content)
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

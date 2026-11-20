import AppKit
import Observation

/// What the toolbar item says for the running Mock Servers (mock-server.md, Where it shows that
/// it runs). Pure: nil means nothing runs and the item is not drawn.
struct MockToolbarContent: Equatable {
    struct Row: Equatable {
        let collection: String
        let port: String
    }

    /// "Mock Server" for one, "2 Mock Servers" for more.
    let title: String
    /// ":3000" for one server; nil for several, whose ports are in the menu.
    let port: String?
    /// Also the accessibility label.
    let tooltip: String
    /// The menu, by Collection name; empty for one server.
    let rows: [Row]

    init?(_ servers: [MockServer]) {
        let servers = servers.sorted { $0.collection < $1.collection }
        switch servers.count {
        case 0: return nil
        case 1:
            title = "Mock Server"
            port = Self.portText(servers[0])
            tooltip = Self.rowTooltip(servers[0]) + ". Click to configure."
            rows = []
        case let count:
            title = "\(count) Mock Servers"
            port = nil
            tooltip = "\(count) Mock Servers running. Click to choose one."
            rows = servers.map { Row(collection: $0.collection, port: Self.portText($0)) }
        }
    }

    static func portText(_ server: MockServer) -> String { ":\(server.port)" }

    /// The Collection row's tooltip, and the toolbar's for one server before its sentence about clicking.
    static func rowTooltip(_ server: MockServer) -> String { "Mock Server running on \(server.url)" }
}

/// The toolbar's Mock Server button (design-system §6 Mock Server toolbar item): a green dot, the
/// words and the port. It shows and reports; the window decides whether it is drawn and what a pick opens.
final class MockToolbarButton: NSButton {
    /// Opens the Mock Server sheet of the Collection named.
    var open: (String) -> Void = { _ in }
    /// True when at least one server runs: the toolbar item is shown exactly then.
    var onShownChange: (Bool) -> Void = { _ in }
    private var servers: [MockServer] = []
    /// The toolbar fixes this view's size once, so the width is set here each time the words change.
    private lazy var widthConstraint = widthAnchor.constraint(equalToConstant: 0)

    init() {
        super.init(frame: .zero)
        bezelStyle = .toolbar
        showsBorderOnlyWhileMouseInside = true
        imagePosition = .imageLeading
        image = Self.dot
        target = self
        action = #selector(clicked)
        translatesAutoresizingMaskIntoConstraints = false
        heightAnchor.constraint(equalToConstant: 28).isActive = true
        widthConstraint.isActive = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    private static let dot = NSImage(size: NSSize(width: 8, height: 8), flipped: false) { rect in
        NSColor.systemGreen.setFill()
        NSBezierPath(ovalIn: rect).fill()
        return true
    }

    /// Follows the window's Mock Servers for as long as both live.
    func bind(_ window: WindowModel) {
        open = { [weak self, weak window] collection in
            guard let window, let host = self?.window else { return }
            MockServerSheet.present(on: host.topSheet, model: window, collection: collection)
        }
        render(window)
    }

    private func render(_ window: WindowModel) {
        let servers = withObservationTracking {
            Array(window.mockServers.values)
        } onChange: { [weak self, weak window] in
            Task { @MainActor in if let window { self?.render(window) } }
        }
        show(servers)
    }

    func show(_ servers: [MockServer]) {
        self.servers = servers
        guard let content = MockToolbarContent(servers) else { return onShownChange(false) }
        let words = NSMutableAttributedString(string: content.title, attributes: [.font: NSFont.systemFont(ofSize: 12), .foregroundColor: NSColor.labelColor])
        if let port = content.port {
            words.append(NSAttributedString(string: " " + port, attributes: [
                .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .regular), .foregroundColor: NSColor.secondaryLabelColor,
            ]))
        }
        attributedTitle = words
        toolTip = content.tooltip
        setAccessibilityLabel(content.tooltip)
        widthConstraint.constant = ceil(intrinsicContentSize.width)
        onShownChange(true)
    }

    /// The running Collections with their ports in secondary text; a pick opens that Collection's sheet.
    func choiceMenu(for servers: [MockServer]) -> NSMenu {
        let menu = NSMenu()
        for row in MockToolbarContent(servers)?.rows ?? [] {
            let entry = NSMenuItem(title: row.collection, action: #selector(picked), keyEquivalent: "")
            entry.target = self
            entry.representedObject = row.collection
            let title = NSMutableAttributedString(string: row.collection, attributes: [.font: NSFont.menuFont(ofSize: 0)])
            title.append(NSAttributedString(string: "  " + row.port, attributes: [
                .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .regular), .foregroundColor: NSColor.secondaryLabelColor,
            ]))
            entry.attributedTitle = title
            menu.addItem(entry)
        }
        return menu
    }

    @objc private func clicked(_ sender: Any?) {
        if servers.count == 1 { return open(servers[0].collection) }
        choiceMenu(for: servers).popUp(positioning: nil, at: NSPoint(x: 0, y: isFlipped ? bounds.height : 0), in: self)
    }

    @objc private func picked(_ sender: NSMenuItem) {
        if let collection = sender.representedObject as? String { open(collection) }
    }
}

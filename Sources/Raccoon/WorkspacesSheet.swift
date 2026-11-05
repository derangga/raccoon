import AppKit
import Observation
import RaccoonDomain

/// The Workspaces sheet (design-system §6): every Workspace with its path and a Remove button. A
/// native sheet, so system colours. It shows what the window holds and asks the window to remove;
/// the rows follow the window's list, so a removal makes its row leave and the sheet shrink.
final class WorkspacesSheet: NSViewController, NSTableViewDataSource, NSTableViewDelegate {
    private static let rowHeight: CGFloat = 48
    private static let visibleRows = 6

    private let window: WindowModel
    let table = NSTableView()
    let hintLabel = NSTextField(labelWithString: "Remove forgets a Workspace. Its folder and secrets stay.")
    let doneButton = NSButton(title: "Done", target: nil, action: nil)
    private let list = NSBox()
    private lazy var listHeight = list.heightAnchor.constraint(equalToConstant: 0)

    private var rows: [WorkspaceTitle] = []
    private var openPath = ""
    private var isOpen = true

    init(window: WindowModel) {
        self.window = window
        super.init(nibName: nil, bundle: nil)
        title = "Workspaces"
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// Shown as a sheet on `parent`; the field focused before is focused again when it closes.
    static func present(on parent: NSWindow, model: WindowModel) {
        guard parent.attachedSheet == nil else { return }
        let sheet = WorkspacesSheet(window: model)
        let restore = EnvironmentsSheet.rememberFocus(in: parent)
        parent.beginSheet(sheetPanel(sheet, focus: sheet.table)) { _ in restore() }
    }

    override func loadView() {
        let root = NSView()
        root.widthAnchor.constraint(equalToConstant: 440).isActive = true

        let heading = NSTextField(labelWithString: "Workspaces")
        heading.font = .systemFont(ofSize: 15, weight: .semibold)
        hintLabel.font = .systemFont(ofSize: 12)
        hintLabel.textColor = .secondaryLabelColor

        table.addTableColumn(NSTableColumn(identifier: .init("workspace")))
        table.headerView = nil
        table.style = .plain
        table.rowHeight = Self.rowHeight
        table.intercellSpacing = .zero
        table.backgroundColor = .clear
        table.selectionHighlightStyle = .none
        table.focusRingType = .none
        table.dataSource = self
        table.delegate = self
        table.setAccessibilityLabel("Workspaces")
        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false
        // A grouped list: the box's colours are dynamic, so they follow Light and Dark.
        list.boxType = .custom
        list.cornerRadius = 8
        list.borderWidth = 1
        list.borderColor = .separatorColor
        list.fillColor = .controlBackgroundColor
        list.contentViewMargins = .zero
        list.contentView = scroll

        doneButton.keyEquivalent = "\r"
        doneButton.target = self
        doneButton.action = #selector(done)

        for view in [heading, hintLabel, list, doneButton] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            root.addSubview(view)
        }
        NSLayoutConstraint.activate([
            heading.topAnchor.constraint(equalTo: root.topAnchor, constant: 20),
            heading.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 20),
            hintLabel.topAnchor.constraint(equalTo: heading.bottomAnchor, constant: 2),
            hintLabel.leadingAnchor.constraint(equalTo: heading.leadingAnchor),
            hintLabel.trailingAnchor.constraint(lessThanOrEqualTo: root.trailingAnchor, constant: -20),
            list.topAnchor.constraint(equalTo: hintLabel.bottomAnchor, constant: 14),
            list.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 20),
            list.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -20),
            listHeight,
            doneButton.topAnchor.constraint(equalTo: list.bottomAnchor, constant: 16),
            doneButton.trailingAnchor.constraint(equalTo: list.trailingAnchor),
            doneButton.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -20),
        ])
        view = root
        render()
    }

    private static var reduceMotion: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }

    /// Re-runs whenever the list or the open Workspace changes, until the sheet closes. A row that
    /// left fades out; anything else (a switch, a title that lost its parent folder) reloads.
    private func render() {
        guard isOpen else { return }
        let (paths, root) = withObservationTracking {
            (window.workspaces, window.dataFolderRoot)
        } onChange: { [weak self] in
            Task { @MainActor in self?.render() }
        }
        let before = rows
        rows = WorkspaceList.titles(paths)
        openPath = Self.standard(root)
        let now = Set(rows.map(\.path))
        let gone = IndexSet(before.indices.filter { !now.contains(before[$0].path) })
        if !gone.isEmpty, rows.count == before.count - gone.count {
            table.removeRows(at: gone, withAnimation: Self.reduceMotion ? .effectFade : [.effectFade, .slideUp])
            // What the survivors show can change: a shorter title, the Open pill, the last row's Remove.
            table.reloadData(forRowIndexes: IndexSet(rows.indices), columnIndexes: [0])
        } else {
            table.reloadData()
        }
        listHeight.constant = CGFloat(min(max(rows.count, 1), Self.visibleRows)) * Self.rowHeight
        fitSheet()
    }

    /// The sheet is as tall as its content, anchored at its top edge.
    private func fitSheet() {
        guard let panel = view.window else { return }
        view.layoutSubtreeIfNeeded()
        let height = panel.frameRect(forContentRect: NSRect(origin: .zero, size: view.fittingSize)).height
        var frame = panel.frame
        guard abs(frame.height - height) > 0.5 else { return }
        frame.origin.y += frame.height - height
        frame.size.height = height
        panel.setFrame(frame, display: true, animate: !Self.reduceMotion)
    }

    private static func standard(_ path: String) -> String { URL(filePath: path).standardized.path }

    // MARK: Table

    func numberOfRows(in tableView: NSTableView) -> Int { rows.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let workspace = rows[row]
        let cell = NSView()

        let title = NSTextField(labelWithString: workspace.title)
        title.font = .systemFont(ofSize: 13, weight: .medium)
        title.lineBreakMode = .byTruncatingTail
        title.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let isDefault = window.isDefaultWorkspace(workspace.path)
        var heading: [NSView] = [title]
        if isDefault { heading.append(Self.pill("Default")) }
        if Self.standard(workspace.path) == openPath { heading.append(Self.pill("Open")) }
        let top = NSStackView(views: heading)
        top.spacing = 6
        top.alignment = .centerY

        let path = NSTextField(labelWithString: (workspace.path as NSString).abbreviatingWithTildeInPath)
        path.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        path.textColor = .secondaryLabelColor
        path.lineBreakMode = .byTruncatingMiddle
        path.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let text = NSStackView(views: [top, path])
        text.orientation = .vertical
        text.alignment = .leading
        text.spacing = 2

        let remove = RemoveButton(target: self, action: #selector(remove(_:)))
        remove.tag = row
        remove.isEnabled = window.canRemoveWorkspace(workspace.path)
        remove.isHidden = isDefault
        remove.setAccessibilityLabel("Remove \(workspace.title)")

        let rule = NSBox()
        rule.boxType = .separator
        rule.isHidden = row == rows.count - 1

        for view in [text, remove, rule] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            cell.addSubview(view)
        }
        NSLayoutConstraint.activate([
            text.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 14),
            text.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            text.trailingAnchor.constraint(lessThanOrEqualTo: remove.leadingAnchor, constant: -8),
            remove.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -14),
            remove.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            remove.widthAnchor.constraint(equalToConstant: 56),
            remove.heightAnchor.constraint(equalToConstant: 24),
            rule.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 14),
            rule.trailingAnchor.constraint(equalTo: cell.trailingAnchor),
            rule.bottomAnchor.constraint(equalTo: cell.bottomAnchor),
        ])
        return cell
    }

    /// A small rounded pill beside the title: "Open" for the Workspace the window shows, "Default"
    /// for the one that cannot be removed.
    private static func pill(_ text: String) -> NSView { Pill(text) }

    @objc private func remove(_ sender: NSButton) {
        guard rows.indices.contains(sender.tag) else { return }
        let root = rows[sender.tag].path
        Task { await window.removeWorkspace(root) }
    }

    @objc private func done() {
        isOpen = false
        if let panel = view.window, let parent = panel.sheetParent { parent.endSheet(panel) }
    }

    /// Esc.
    override func cancelOperation(_ sender: Any?) { done() }
}

/// A row's Remove: quiet text that turns red under the pointer, dims while pressed and goes
/// tertiary when it cannot be used, so a column of them does not shout.
private final class RemoveButton: NSButton {
    private var hovering = false { didSet { restyle() } }

    init(target: AnyObject?, action: Selector) {
        super.init(frame: .zero)
        self.target = target
        self.action = action
        isBordered = false
        alignment = .right
        focusRingType = .none
        restyle()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var isEnabled: Bool { didSet { restyle() } }
    override var isHighlighted: Bool { didSet { alphaValue = isHighlighted ? 0.6 : 1 } }

    override func updateTrackingAreas() {
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self))
        super.updateTrackingAreas()
    }

    override func mouseEntered(with event: NSEvent) { hovering = true }
    override func mouseExited(with event: NSEvent) { hovering = false }

    private func restyle() {
        let color: NSColor = !isEnabled ? .tertiaryLabelColor : hovering ? .systemRed : .secondaryLabelColor
        attributedTitle = NSAttributedString(string: "Remove", attributes: [.foregroundColor: color, .font: NSFont.systemFont(ofSize: 12)])
    }
}

/// A label on a 4 pt rounded fill, as wide as its text. Drawn, not an NSBox, which has no size of
/// its own and let two pills in one row overlap. The colours resolve at draw time, so Light and
/// Dark follow the view's appearance.
private final class Pill: NSView {
    private let text: NSAttributedString

    init(_ string: String) {
        text = NSAttributedString(string: string, attributes: [
            .font: NSFont.systemFont(ofSize: 10, weight: .semibold),
            .foregroundColor: NSColor.secondaryLabelColor,
        ])
        super.init(frame: .zero)
        setContentHuggingPriority(.required, for: .horizontal)
        setContentCompressionResistancePriority(.required, for: .horizontal)
        setAccessibilityElement(true)
        setAccessibilityRole(.staticText)
        setAccessibilityLabel(string)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var intrinsicContentSize: NSSize {
        let size = text.size()
        return NSSize(width: ceil(size.width) + 12, height: ceil(size.height) + 2)
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.quaternaryLabelColor.setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 4, yRadius: 4).fill()
        let size = text.size()
        text.draw(at: NSPoint(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2))
    }
}

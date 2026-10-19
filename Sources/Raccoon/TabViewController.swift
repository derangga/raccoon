import AppKit
import RaccoonDomain

/// The selected Tab: the URL bar, then the RequestEditor over the ResponseViewer in a Split.
/// There is one for the window; switching Tabs rebinds it rather than building new views.
final class TabViewController: NSViewController, NSMenuItemValidation {
    private(set) var model: TabModel
    private let theme: ThemeEnvironment
    private let split = EditorSplitView()
    let urlBar: URLBar
    let editor: RequestEditor
    let viewer: ResponseViewer

    init(model: TabModel, theme: ThemeEnvironment) {
        self.model = model
        self.theme = theme
        urlBar = URLBar(model: model, theme: theme)
        editor = RequestEditor(model: model, theme: theme)
        viewer = ResponseViewer(model: model, theme: theme)
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func loadView() {
        split.background = theme.color(.background)
        split.border = theme.color(.border)
        split.addSubview(editor)
        split.addSubview(viewer)

        let root = NSView()
        root.wantsLayer = true
        root.layer?.backgroundColor = theme.color(.background).cgColor
        for part in [urlBar, split] as [NSView] {
            part.translatesAutoresizingMaskIntoConstraints = false
            root.addSubview(part)
        }
        NSLayoutConstraint.activate([
            urlBar.topAnchor.constraint(equalTo: root.topAnchor),
            urlBar.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            urlBar.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            split.topAnchor.constraint(equalTo: urlBar.bottomAnchor),
            split.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            split.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            split.bottomAnchor.constraint(equalTo: root.bottomAnchor),
        ])
        view = root
    }

    /// Shows another Tab in the same views, keeping where the old one was.
    func bind(_ model: TabModel) {
        guard model !== self.model else { return }
        // A field being edited writes its text to the Tab it was typed in.
        view.window?.makeFirstResponder(nil)
        self.model.viewState = TabModel.ViewState(
            section: editor.selected, body: editor.bodyPane.textView.place, response: viewer.textView.place
        )
        // ponytail: one window undo stack, and its actions read whichever Tab is bound, so a
        // switch drops them. An UndoManager per TabModel keeps them if that is missed.
        undoManager?.removeAllActions()
        self.model = model
        urlBar.bind(model)
        editor.bind(model)
        viewer.bind(model)
        editor.select(model.viewState.section)
        view.layoutSubtreeIfNeeded()
        editor.bodyPane.textView.restore(model.viewState.body)
        viewer.textView.restore(model.viewState.response)
    }

    /// Copy as Curl from the Edit menu and the URL bar's menu, through the responder chain, so it
    /// is the selected Tab's.
    @objc func copyAsCurl(_ sender: Any?) { model.copyAsCurl() }

    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        item.action == #selector(copyAsCurl) ? model.curlCommand != nil : true
    }
}

extension NSTextView {
    var place: TabModel.TextPlace {
        TabModel.TextPlace(origin: enclosingScrollView?.contentView.bounds.origin ?? .zero, selection: selectedRange())
    }

    /// A new storage is laid out from the top only, so the text is laid out down to the place
    /// before scrolling there.
    func restore(_ place: TabModel.TextPlace) {
        let length = (string as NSString).length
        let start = min(place.selection.location, length)
        setSelectedRange(NSRange(location: start, length: min(place.selection.length, length - start)))
        guard let scroll = enclosingScrollView, let layoutManager, let textContainer else { return }
        layoutManager.ensureLayout(forBoundingRect: NSRect(x: 0, y: 0, width: .greatestFiniteMagnitude,
                                                           height: place.origin.y + scroll.contentView.bounds.height),
                                   in: textContainer)
        sizeToFit()
        scroll.contentView.scroll(to: place.origin)
        scroll.reflectScrolledClipView(scroll.contentView)
    }
}

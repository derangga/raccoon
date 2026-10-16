import AppKit
import RaccoonDomain

/// The selected Tab: the URL bar, then the RequestEditor over the ResponseViewer in a Split.
final class TabViewController: NSViewController {
    private let model: TabModel
    private let theme: ThemeEnvironment
    private let split = EditorSplitView()

    init(model: TabModel, theme: ThemeEnvironment) {
        self.model = model
        self.theme = theme
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func loadView() {
        let urlBar = URLBar(model: model, theme: theme)
        split.background = theme.color(.background)
        split.border = theme.color(.border)
        split.addSubview(RequestEditor(model: model, theme: theme))
        split.addSubview(ResponseViewer(model: model, theme: theme))

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
}

import AppKit
import Observation
import RaccoonDomain

/// The selected Tab: the URL bar, then the RequestEditor over the ResponseViewer in a Split.
// ponytail: tracer Response pane; the full Response viewer states replace it.
final class TabViewController: NSViewController {
    private let model: TabModel
    private let theme: ThemeEnvironment
    private let statusLabel = NSTextField(labelWithString: "")
    private let bodyView = NSTextView()
    private let split = EditorSplitView()

    init(model: TabModel, theme: ThemeEnvironment) {
        self.model = model
        self.theme = theme
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func loadView() {
        let mono = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        statusLabel.font = .monospacedSystemFont(ofSize: 12, weight: .bold)

        bodyView.isEditable = false
        bodyView.font = mono
        bodyView.drawsBackground = false
        bodyView.isVerticallyResizable = true
        bodyView.autoresizingMask = [.width]
        bodyView.textContainer?.widthTracksTextView = true
        let scroll = NSScrollView()
        scroll.documentView = bodyView
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false

        let urlRow = URLBar(model: model, theme: theme)

        let response = NSStackView(views: [statusLabel, scroll])
        response.orientation = .vertical
        response.alignment = .leading
        response.spacing = 8
        response.edgeInsets = NSEdgeInsets(top: 8, left: 12, bottom: 8, right: 12)
        scroll.widthAnchor.constraint(equalTo: response.widthAnchor, constant: -24).isActive = true
        // The split sets its panes' frames, so the stack sits inside a plain view it can size.
        let responsePane = NSView()
        responsePane.wantsLayer = true
        responsePane.layer?.backgroundColor = theme.color(.backgroundRecessed).cgColor
        response.translatesAutoresizingMaskIntoConstraints = false
        responsePane.addSubview(response)
        NSLayoutConstraint.activate([
            response.topAnchor.constraint(equalTo: responsePane.topAnchor),
            response.bottomAnchor.constraint(equalTo: responsePane.bottomAnchor),
            response.leadingAnchor.constraint(equalTo: responsePane.leadingAnchor),
            response.trailingAnchor.constraint(equalTo: responsePane.trailingAnchor),
        ])

        split.background = theme.color(.background)
        split.border = theme.color(.border)
        split.addSubview(RequestEditor(model: model, theme: theme))
        split.addSubview(responsePane)

        let root = NSView()
        root.wantsLayer = true
        root.layer?.backgroundColor = theme.color(.background).cgColor
        for part in [urlRow, split] as [NSView] {
            part.translatesAutoresizingMaskIntoConstraints = false
            root.addSubview(part)
        }
        NSLayoutConstraint.activate([
            urlRow.topAnchor.constraint(equalTo: root.topAnchor),
            urlRow.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            urlRow.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            split.topAnchor.constraint(equalTo: urlRow.bottomAnchor),
            split.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            split.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            split.bottomAnchor.constraint(equalTo: root.bottomAnchor),
        ])
        view = root
        render()
    }


    /// Redraws from the Tab's Response state, and again whenever it changes.
    private func render() {
        withObservationTracking {
            let (status, color, body) = Self.text(for: model.tab.response, showsSpinner: model.showsSpinner)
            statusLabel.stringValue = status
            statusLabel.textColor = theme.color(color)
            bodyView.string = body
            bodyView.textColor = theme.color(.text)
        } onChange: { [weak self] in
            Task { @MainActor in self?.render() }
        }
        // Time passing is not a change Observation sees: look again when the spinner is due.
        if case .sending = model.tab.response, !model.showsSpinner {
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(150))
                self?.render()
            }
        }
    }

    static func text(for state: ResponseState, showsSpinner: Bool) -> (status: String, color: ColorToken, body: String) {
        switch state {
        case .idle:
            ("", .textTertiary, "Send a request to see the Response here.")
        case .sending where !showsSpinner:
            ("", .textSecondary, "")
        case .sending:
            ("Sending…", .textSecondary, "Waiting for the server.")
        case .received(let response):
            received(response)
        case .failed(let error):
            ("Failed", .statusFailed, "\(error)")
        case .notSent(.invalidURL(let text)):
            ("Not sent", .statusFailed, "Invalid URL: \(text)")
        case .notSent(.undefined(let names)):
            ("Not sent", .statusFailed, "Not defined: \(names.map(\.rawValue).joined(separator: ", "))")
        }
    }

    private static func received(_ response: Response) -> (status: String, color: ColorToken, body: String) {
        let line = StatusLine(status: response.status, elapsed: response.elapsed, byteCount: response.byteCount)
        return ("\(line.code) \(line.reason) · \(line.elapsed) · \(line.size)", line.token, String(decoding: response.body, as: UTF8.self))
    }
}

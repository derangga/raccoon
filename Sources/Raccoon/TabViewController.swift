import AppKit
import Observation
import RaccoonDomain

/// The editor and Response viewer for the selected Tab. For now: a URL field, Send, the
/// Headers table, and the status and raw body of the last send.
// ponytail: tracer only. The URL bar, the RequestEditor and the full Response viewer states
// replace these views in their own features.
final class TabViewController: NSViewController, NSTextFieldDelegate {
    private let model: TabModel
    private let theme: ThemeEnvironment
    private let urlField = NSTextField()
    private let sendButton = NSButton(title: "Send", target: nil, action: nil)
    private let statusLabel = NSTextField(labelWithString: "")
    private let bodyView = NSTextView()
    private let headersLabel = NSTextField(labelWithString: "")
    private lazy var headersTable = KeyValueTable(theme: theme)

    init(model: TabModel, theme: ThemeEnvironment) {
        self.model = model
        self.theme = theme
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func loadView() {
        let mono = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        urlField.font = mono
        urlField.placeholderString = "https://"
        urlField.stringValue = model.tab.definition.url
        urlField.delegate = self
        urlField.cell?.isScrollable = true
        urlField.cell?.wraps = false

        sendButton.target = self
        sendButton.action = #selector(send(_:))
        sendButton.keyEquivalent = "\r"
        sendButton.keyEquivalentModifierMask = .command
        sendButton.bezelColor = theme.color(.accent)

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

        let urlRow = NSStackView(views: [urlField, sendButton])
        urlRow.spacing = 8
        headersLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        headersLabel.textColor = theme.color(.textTertiary)
        headersTable.onChange = { [weak self] in self?.model.tab.definition.headers = $0 }
        headersTable.heightAnchor.constraint(equalToConstant: 200).isActive = true

        let stack = NSStackView(views: [urlRow, headersLabel, headersTable, statusLabel, scroll])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.edgeInsets = NSEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)
        urlRow.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -24).isActive = true
        scroll.widthAnchor.constraint(equalTo: urlRow.widthAnchor).isActive = true
        headersTable.widthAnchor.constraint(equalTo: urlRow.widthAnchor).isActive = true
        view = stack
        render()
    }

    func controlTextDidChange(_ notification: Notification) {
        model.tab.definition.url = urlField.stringValue
    }

    @objc private func send(_ sender: Any?) {
        model.send()
    }

    /// Redraws from the Tab's Response state, and again whenever it changes.
    private func render() {
        withObservationTracking {
            let headers = model.tab.definition.headers
            headersLabel.stringValue = "Headers \(headers.count)"
            headersTable.setRows(headers)
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

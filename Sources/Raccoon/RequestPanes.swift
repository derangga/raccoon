import AppKit
import RaccoonDomain

/// The Settings section: two checkboxes, each with its hint (design-system.md §6 Request Settings).
/// No compression row: URLSession always asks for and decodes gzip (Open UI question 10).
final class SettingsPane: NSView {
    let checkboxes: [NSButton]
    let insecureTLSHint = NSTextField(wrappingLabelWithString: "Accept certificates the system does not trust, for this Request only.")
    var onChange: (RequestSettings) -> Void = { _ in }

    init(theme: ThemeEnvironment) {
        checkboxes = ["Allow insecure TLS", "Follow redirects"].map { NSButton(checkboxWithTitle: $0, target: nil, action: nil) }
        super.init(frame: .zero)
        for box in checkboxes {
            box.target = self
            box.action = #selector(toggled)
        }
        insecureTLSHint.font = .systemFont(ofSize: 11)
        insecureTLSHint.textColor = theme.color(.textTertiary)
        let insecure = NSStackView(views: [checkboxes[0], insecureTLSHint])
        insecure.orientation = .vertical
        insecure.alignment = .leading
        insecure.spacing = 2
        let column = NSStackView(views: [insecure, checkboxes[1]])
        column.orientation = .vertical
        column.alignment = .leading
        column.spacing = 10
        column.translatesAutoresizingMaskIntoConstraints = false
        addSubview(column)
        NSLayoutConstraint.activate([
            column.topAnchor.constraint(equalTo: topAnchor),
            column.leadingAnchor.constraint(equalTo: leadingAnchor),
            column.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor),
            // The hint lines up with the checkbox title, not the box.
            insecureTLSHint.leadingAnchor.constraint(equalTo: insecure.leadingAnchor, constant: 20),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func setSettings(_ settings: RequestSettings) {
        checkboxes[0].state = settings.allowsInsecureTLS ? .on : .off
        checkboxes[1].state = settings.followsRedirects ? .on : .off
    }

    @objc private func toggled() {
        onChange(RequestSettings(allowsInsecureTLS: checkboxes[0].state == .on, followsRedirects: checkboxes[1].state == .on))
    }
}

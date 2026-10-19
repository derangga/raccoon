import AppKit
import Foundation
@testable import Raccoon
import RaccoonDomain
import RaccoonTesting
import Testing

@MainActor
struct ThemeControllerTests {
    let catalog = ThemeCatalog.load()

    func flavor(_ name: String) -> Flavor { catalog.themes[0].flavors.first { $0.name == name }! }

    /// Lets the Tasks that observation changes schedule run.
    func settle() async {
        for _ in 0..<5 { await Task.yield() }
    }

    @Test func `a paint runs now and again when the Flavor changes`() async {
        let theme = ThemeEnvironment(catalog: catalog, isDark: false)
        let field = NSTextField(labelWithString: "")
        theme.paint(field) { $0.textColor = $1.color(.text) }
        #expect(field.textColor == theme.color(.text))

        theme.flavor = flavor("Mocha")
        await settle()

        #expect(field.textColor == ThemeEnvironment(catalog: catalog, isDark: true).color(.text))
    }

    /// A UserDefaults suite of its own per test, emptied first.
    func defaults(_ name: String = #function) -> UserDefaults {
        let suite = "ThemeControllerTests.\(name)"
        UserDefaults().removePersistentDomain(forName: suite)
        return UserDefaults(suiteName: suite)!
    }

    /// An appearance source the test can flip without touching the app's own appearance.
    func source(_ name: NSAppearance.Name) -> NSView {
        let view = NSView()
        view.appearance = NSAppearance(named: name)
        return view
    }

    @Test func `a choice round-trips through UserDefaults`() {
        let defaults = defaults()
        let choice = ThemeChoice(theme: "Catppuccin", light: "Latte", dark: "Frappé")
        ThemeController(defaults: defaults, catalog: catalog, appearanceSource: source(.aqua)).choice = choice

        let relaunched = ThemeController(defaults: defaults, catalog: catalog, appearanceSource: source(.darkAqua))

        #expect(relaunched.choice == choice)
        #expect(relaunched.theme.flavor.name == "Frappé")
    }

    @Test func `nothing stored shows Latte in light and Mocha in dark`() {
        #expect(ThemeController(defaults: defaults(), catalog: catalog, appearanceSource: source(.aqua)).theme.flavor.name == "Latte")
        #expect(ThemeController(defaults: defaults(), catalog: catalog, appearanceSource: source(.darkAqua)).theme.flavor.name == "Mocha")
    }

    @Test func `a stored unknown Theme falls back to Latte and Mocha`() {
        let defaults = defaults()
        defaults.set(["theme": "Dracula", "light": "Latte", "dark": "Frappé"], forKey: ThemeController.key)

        let controller = ThemeController(defaults: defaults, catalog: catalog, appearanceSource: source(.darkAqua))

        #expect(controller.choice == .default)
        #expect(controller.theme.flavor.name == "Mocha")
    }

    @Test func `a choice applies at once`() {
        let controller = ThemeController(defaults: defaults(), catalog: catalog, appearanceSource: source(.darkAqua))

        controller.choice = ThemeChoice(theme: "Catppuccin", light: "Latte", dark: "Macchiato")

        #expect(controller.theme.flavor.name == "Macchiato")
    }

    /// Every colour a view holds as a property, a layer or text attributes, as `#rrggbb`.
    /// Colours read in `draw(_:)` are not here: those views repaint by redrawing.
    func colours(in view: NSView) -> [String: String] {
        var found: [String: String] = [:]
        func add(_ color: NSColor?, _ place: String) {
            guard let srgb = color?.usingColorSpace(.sRGB) else { return }
            let hex = [srgb.redComponent, srgb.greenComponent, srgb.blueComponent].map { String(format: "%02x", Int(($0 * 255).rounded())) }.joined()
            found["#" + hex, default: place] += ""
        }
        func add(_ cgColor: CGColor?, _ place: String) { add(cgColor.flatMap(NSColor.init(cgColor:)), place) }
        func add(_ text: NSAttributedString?, _ place: String) {
            guard let text else { return }
            text.enumerateAttributes(in: NSRange(location: 0, length: text.length)) { attributes, _, _ in
                add(attributes[.foregroundColor] as? NSColor, place)
                add(attributes[.backgroundColor] as? NSColor, place)
            }
        }
        func walk(_ view: NSView) {
            let place = String(describing: type(of: view))
            add(view.layer?.backgroundColor, place)
            add(view.layer?.borderColor, place)
            for sublayer in view.layer?.sublayers ?? [] { add(sublayer.backgroundColor, place + " sublayer") }
            switch view {
            case let field as NSTextField:
                add(field.textColor, place)
                add(field.attributedStringValue, place)
                add(field.placeholderAttributedString, place + " placeholder")
            case let textView as NSTextView:
                add(textView.textColor, place)
                add(textView.insertionPointColor, place)
                add(textView.typingAttributes[.foregroundColor] as? NSColor, place)
                add(textView.textStorage, place + " storage")
            case let box as NSBox:
                add(box.fillColor, place)
            case let table as NSTableView:
                add(table.gridColor, place)
                add(table.backgroundColor, place)
            case let split as EditorSplitView:
                add(split.background, place)
                add(split.border, place)
            case let image as NSImageView:
                add(image.contentTintColor, place)
            default: break
            }
            if let button = view as? NSButton {
                add(button.attributedTitle, place)
                add(button.contentTintColor, place)
                add(button.bezelColor, place)
            }
            view.subviews.forEach(walk)
        }
        walk(view)
        return found
    }

    @Test func `switching the Flavor leaves no colour of the old one on the Tab`() async throws {
        let json = Data(#"{"name": "raccoon", "count": 2, "ok": true, "none": null}"#.utf8)
        let response = Response(status: 200, headers: [.init(name: "Content-Type", value: "application/json")], body: json,
                                elapsed: .milliseconds(12), byteCount: json.count)
        let model = TabModel(transport: ScriptedTransport(.success(response)), secrets: InMemorySecretStore(), files: DictionaryFileReading([:]),
                             instants: FixedInstantSource(.now), clipboard: RecordingClipboardWriter())
        model.tab.definition.url = "http://localhost/items?page=2&size=10"
        model.tab.definition.headers = [Row(name: "Accept", value: "application/json")]
        model.tab.definition.body = .raw(.json, #"{"name": "raccoon", "count": 2}"#)
        model.send()
        await model.inFlight?.value
        await model.presenting?.value

        let theme = ThemeEnvironment(catalog: catalog, isDark: false)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1000, height: 800), styleMask: [], backing: .buffered, defer: false)
        let controller = TabViewController(model: model, theme: theme)
        window.contentView = controller.view
        controller.view.layoutSubtreeIfNeeded()

        let mocha = flavor("Mocha")
        func hexes(_ flavor: Flavor) -> Set<String> {
            Set(ColorToken.allCases.map { String(format: "#%02x%02x%02x", flavor[$0].red, flavor[$0].green, flavor[$0].blue) })
        }
        let latteOnly = hexes(flavor("Latte")).subtracting(hexes(mocha))
        #expect(!colours(in: controller.view).keys.filter(latteOnly.contains).isEmpty, "the sweep sees Latte before the switch")

        theme.flavor = mocha
        await settle()
        controller.view.layoutSubtreeIfNeeded()

        let left = colours(in: controller.view).filter { latteOnly.contains($0.key) }
        #expect(left.isEmpty, "\(left)")
    }

    @Test func `flipping the appearance switches to the other Flavor`() async {
        let view = source(.aqua)
        let controller = ThemeController(defaults: defaults(), catalog: catalog, appearanceSource: view)
        #expect(controller.theme.flavor.name == "Latte")

        view.appearance = NSAppearance(named: .darkAqua)
        await settle()

        #expect(controller.theme.flavor.name == "Mocha")
    }
}

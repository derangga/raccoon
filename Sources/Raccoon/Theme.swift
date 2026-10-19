import AppKit
import Observation
import RaccoonDomain

/// The Themes that ship inside the app.
struct ThemeCatalog {
    let themes: [Theme]

    /// A bundled file that does not decode is our bug, not the user's: it traps (§4), and
    /// ThemeCatalogTests fails before such a file can ship.
    static func load(from bundle: Bundle = .module) -> ThemeCatalog {
        guard let url = bundle.url(forResource: "catppuccin", withExtension: "json"), let data = try? Data(contentsOf: url) else {
            preconditionFailure("catppuccin.json is missing from the app bundle")
        }
        do throws(ThemeFileError) {
            return ThemeCatalog(themes: [try ThemeFile.decode(data)])
        } catch {
            preconditionFailure("catppuccin.json: \(error)")
        }
    }
}

/// The current Flavor, the one value content views read their colors from. ThemeController
/// sets it; a view reads it inside its `render()` or a `paint`, so a change re-colours it.
@Observable
final class ThemeEnvironment {
    var flavor: Flavor

    init(flavor: Flavor) {
        self.flavor = flavor
    }

    /// The default choice's Flavor for an appearance, for views built without a ThemeController.
    convenience init(catalog: ThemeCatalog, isDark: Bool) {
        self.init(flavor: ThemeChoice.default.flavor(for: isDark ? .dark : .light, in: catalog.themes))
    }

    func color(_ token: ColorToken) -> NSColor {
        let color = flavor[token]
        return NSColor(srgbRed: CGFloat(color.red) / 255, green: CGFloat(color.green) / 255, blue: CGFloat(color.blue) / 255, alpha: 1)
    }

    /// Runs `paint` now and again each time the Flavor changes, for as long as `owner` lives.
    /// Every colour set outside a `render()` goes through here, so none is read once and kept.
    func paint<Owner: AnyObject & Sendable>(_ owner: Owner, _ paint: @escaping @MainActor (Owner, ThemeEnvironment) -> Void) {
        withObservationTracking {
            _ = flavor
            paint(owner, self)
        } onChange: { [weak self, weak owner] in
            Task { @MainActor in if let self, let owner { self.paint(owner, paint) } }
        }
    }
}

/// Keeps ThemeEnvironment on the chosen Flavor for the appearance: reads the ThemeChoice at
/// launch, writes it when it changes, and follows the source's appearance for its lifetime.
final class ThemeController {
    static let key = "ThemeChoice"

    let theme: ThemeEnvironment
    private let catalog: ThemeCatalog
    private let defaults: UserDefaults
    private let appearance: () -> Flavor.Appearance
    private var observation: NSKeyValueObservation?

    var choice: ThemeChoice {
        didSet {
            defaults.set(choice.stored, forKey: Self.key)
            apply()
        }
    }

    /// `appearanceSource` is NSApp in the app.
    init<Source: NSObject & NSAppearanceCustomization>(defaults: UserDefaults, catalog: ThemeCatalog, appearanceSource: Source) {
        self.defaults = defaults
        self.catalog = catalog
        appearance = {
            appearanceSource.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? .dark : .light
        }
        choice = ThemeChoice.decode(defaults.dictionary(forKey: Self.key) as? [String: String], themes: catalog.themes)
        theme = ThemeEnvironment(flavor: choice.flavor(for: appearance(), in: catalog.themes))
        observation = appearanceSource.observe(\.effectiveAppearance) { [weak self] _, _ in
            MainActor.assumeIsolated { self?.apply() }
        }
    }

    private func apply() {
        let flavor = choice.flavor(for: appearance(), in: catalog.themes)
        if flavor != theme.flavor { theme.flavor = flavor }
    }
}

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

/// The current Flavor, the one value content views read their colors from.
/// Following appearance changes and the stored ThemeChoice come with the Theme menu.
@Observable
final class ThemeEnvironment {
    private(set) var flavor: Flavor

    init(catalog: ThemeCatalog, isDark: Bool) {
        let name = isDark ? "Mocha" : "Latte"
        guard let flavor = catalog.themes.first?.flavors.first(where: { $0.name == name }) else {
            preconditionFailure("The bundled Theme has no \(name)")
        }
        self.flavor = flavor
    }

    func color(_ token: ColorToken) -> NSColor {
        let color = flavor[token]
        return NSColor(srgbRed: CGFloat(color.red) / 255, green: CGFloat(color.green) / 255, blue: CGFloat(color.blue) / 255, alpha: 1)
    }
}

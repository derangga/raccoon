import Foundation
import RaccoonDomain
import Testing

struct ThemeChoiceTests {
    /// Catppuccin's four Flavors, every token one color: these tests read names, not colors.
    let themes: [Theme] = {
        let colors = Dictionary(uniqueKeysWithValues: ColorToken.allCases.map { ($0.rawValue, "#000000") })
        let flavors = [("Latte", "light"), ("Frappé", "dark"), ("Macchiato", "dark"), ("Mocha", "dark")]
            .map { ["name": $0.0, "appearance": $0.1, "colors": colors] as [String: Any] }
        let json: [String: Any] = ["name": "Catppuccin", "flavors": flavors]
        return [try! ThemeFile.decode(try! JSONSerialization.data(withJSONObject: json))]
    }()

    @Test(arguments: [(Flavor.Appearance.light, "Latte"), (.dark, "Frappé")])
    func `the appearance picks its own Flavor`(appearance: Flavor.Appearance, expected: String) {
        let choice = ThemeChoice(theme: "Catppuccin", light: "Latte", dark: "Frappé")

        #expect(choice.flavor(for: appearance, in: themes).name == expected)
    }

    @Test func `a stored choice of known names decodes as stored`() {
        let stored = ["theme": "Catppuccin", "light": "Latte", "dark": "Macchiato"]

        #expect(ThemeChoice.decode(stored, themes: themes) == ThemeChoice(theme: "Catppuccin", light: "Latte", dark: "Macchiato"))
    }

    @Test(arguments: [
        nil,
        ["theme": "Dracula", "light": "Latte", "dark": "Mocha"],
        ["theme": "Catppuccin", "light": "Daylight", "dark": "Mocha"],
        ["theme": "Catppuccin", "light": "Latte", "dark": "Midnight"],
        ["theme": "Catppuccin", "light": "Mocha", "dark": "Mocha"],
        ["theme": "Catppuccin", "light": "Latte", "dark": "Latte"],
        ["theme": "Catppuccin", "light": "Latte"],
    ] as [[String: String]?])
    func `a stored choice that does not resolve falls back to Latte and Mocha`(stored: [String: String]?) {
        let choice = ThemeChoice.decode(stored, themes: themes)

        #expect(choice == ThemeChoice(theme: "Catppuccin", light: "Latte", dark: "Mocha"))
        #expect(choice == .default)
    }

    @Test func `a choice is stored as the three names`() {
        let choice = ThemeChoice(theme: "Catppuccin", light: "Latte", dark: "Frappé")

        #expect(choice.stored == ["theme": "Catppuccin", "light": "Latte", "dark": "Frappé"])
        #expect(ThemeChoice.decode(choice.stored, themes: themes) == choice)
    }
}

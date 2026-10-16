import Foundation
import RaccoonDomain
import Testing

struct ThemeFileTests {
    /// A theme file with one Flavor, every token set to `hex` unless overridden.
    func file(hex: String = "#eff1f5", drop: ColorToken? = nil, extra: [String: String] = [:]) -> Data {
        var colors = Dictionary(uniqueKeysWithValues: ColorToken.allCases.filter { $0 != drop }.map { ($0.rawValue, hex) })
        colors.merge(extra) { $1 }
        let json: [String: Any] = ["name": "Catppuccin", "flavors": [["name": "Latte", "appearance": "light", "colors": colors]]]
        return try! JSONSerialization.data(withJSONObject: json)
    }

    @Test func `a complete file decodes every token`() throws {
        let theme = try ThemeFile.decode(file())

        #expect(theme.name == "Catppuccin")
        #expect(theme.flavors.map(\.name) == ["Latte"])
        #expect(theme.flavors[0].appearance == .light)
        #expect(theme.flavors[0][.background] == ThemeColor(red: 0xEF, green: 0xF1, blue: 0xF5))
    }

    @Test func `a missing token is named`() {
        #expect(throws: ThemeFileError.missingToken(flavor: "Latte", token: "jsonKey")) { try ThemeFile.decode(file(drop: .jsonKey)) }
    }

    @Test func `a token the app does not know is named`() {
        #expect(throws: ThemeFileError.unknownToken(flavor: "Latte", token: "sparkle")) {
            try ThemeFile.decode(file(extra: ["sparkle": "#000000"]))
        }
    }

    @Test(arguments: ["eff1f5", "#eff1f", "#eff1g5", "#eff1f5ff"])
    func `a color that is not #rrggbb is named`(hex: String) {
        #expect(throws: ThemeFileError.badColor(flavor: "Latte", token: "background", value: hex)) {
            try ThemeFile.decode(file(hex: hex))
        }
    }

    @Test func `bytes that are not a theme file are undecodable`() {
        #expect(throws: ThemeFileError.self) { try ThemeFile.decode(Data("[]".utf8)) }
    }
}

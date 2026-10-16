import AppKit
import Foundation
@testable import Raccoon
import RaccoonDomain
import Testing

@MainActor
struct ThemeCatalogTests {
    let catalog = ThemeCatalog.load()

    @Test func `the bundled catalog has Catppuccin's four Flavors`() {
        #expect(catalog.themes.map(\.name) == ["Catppuccin"])
        #expect(catalog.themes[0].flavors.map(\.name) == ["Latte", "Frappé", "Macchiato", "Mocha"])
        #expect(catalog.themes[0].flavors.map(\.appearance) == [.light, .dark, .dark, .dark])
    }

    @Test func `every bundled Flavor has every token`() {
        for flavor in catalog.themes.flatMap(\.flavors) {
            for token in ColorToken.allCases {
                _ = flavor[token]  // traps on a missing token, which fails the run
            }
        }
    }

    @Test func `launch picks Latte for light and Mocha for dark`() {
        #expect(ThemeEnvironment(catalog: catalog, isDark: false).flavor.name == "Latte")
        #expect(ThemeEnvironment(catalog: catalog, isDark: true).flavor.name == "Mocha")
    }

    @Test func `a token becomes the sRGB NSColor of its hex`() throws {
        let color = ThemeEnvironment(catalog: catalog, isDark: false).color(.background)  // Latte base #eff1f5
        let srgb = try #require(color.usingColorSpace(.sRGB))
        #expect(Int((srgb.redComponent * 255).rounded()) == 0xEF)
        #expect(Int((srgb.greenComponent * 255).rounded()) == 0xF1)
        #expect(Int((srgb.blueComponent * 255).rounded()) == 0xF5)
    }

    @Test func `the app target holds no hex color literals`() throws {
        let sources = URL(filePath: #filePath).deletingLastPathComponent().appending(path: "../../Sources/Raccoon").standardized
        let files = try #require(FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil))
            .compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" }
        #expect(!files.isEmpty)
        for file in files {
            let text = try String(contentsOf: file, encoding: .utf8)
            #expect(text.firstMatch(of: /#[0-9a-fA-F]{6}\b|0x[0-9a-fA-F]{6}\b/) == nil, "\(file.lastPathComponent)")
        }
    }
}

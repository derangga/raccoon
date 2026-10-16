import Foundation

/// A named family of Flavors for the content areas. Chrome follows the system instead.
public struct Theme: Equatable, Sendable {
    public var name: String
    public var flavors: [Flavor]

    public init(name: String, flavors: [Flavor]) {
        self.name = name
        self.flavors = flavors
    }
}

/// One color scheme within a Theme. Holds every ColorToken: ThemeFile.decode refuses a file that does not.
public struct Flavor: Equatable, Sendable {
    public enum Appearance: String, Equatable, Sendable, Decodable {
        case light, dark
    }

    public var name: String
    public var appearance: Appearance
    private var colors: [ColorToken: ThemeColor]

    init(name: String, appearance: Appearance, colors: [ColorToken: ThemeColor]) {
        self.name = name
        self.appearance = appearance
        self.colors = colors
    }

    public subscript(token: ColorToken) -> ThemeColor {
        guard let color = colors[token] else { preconditionFailure("Flavor \(name) has no \(token)") }
        return color
    }
}

/// The names views ask for. One case per key in design/ui/themes/catppuccin.json.
public enum ColorToken: String, CaseIterable, Sendable {
    case background
    case backgroundElevated
    case backgroundRecessed
    case border
    case selection
    case rowHover
    case text
    case textSecondary
    case textTertiary
    case textDisabled
    case textOnAccent
    case accent
    case focusRing
    case methodGet
    case methodPost
    case methodPut
    case methodPatch
    case methodDelete
    case methodHead
    case methodOptions
    case methodOther
    case status1xx
    case status2xx
    case status3xx
    case status4xx
    case status5xx
    case statusFailed
    case jsonKey
    case jsonString
    case jsonNumber
    case jsonBoolean
    case jsonNull
    case jsonPunctuation
    case xmlTag
    case xmlAttribute
    case xmlValue
    case variableDefined
    case variableSecret
    case variableUndefined
    case dirtyDot
    case warning
    case error
    case success
}

/// An sRGB color, 8 bits per channel, as the theme file writes it (`#rrggbb`).
public struct ThemeColor: Equatable, Sendable {
    public var red: UInt8
    public var green: UInt8
    public var blue: UInt8

    public init(red: UInt8, green: UInt8, blue: UInt8) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    init?(hex: String) {
        guard hex.count == 7, hex.first == "#", let value = UInt32(hex.dropFirst(), radix: 16) else { return nil }
        self.init(red: UInt8(value >> 16 & 0xFF), green: UInt8(value >> 8 & 0xFF), blue: UInt8(value & 0xFF))
    }
}

/// A bundled theme file did not decode. The file ships inside the app, so the caller treats this as a bug (§4).
public enum ThemeFileError: Error, Equatable, Sendable {
    case undecodable(String)
    case missingToken(flavor: String, token: String)
    case unknownToken(flavor: String, token: String)
    case badColor(flavor: String, token: String, value: String)
}

public enum ThemeFile {
    private struct File: Decodable {
        struct FlavorEntry: Decodable {
            var name: String
            var appearance: Flavor.Appearance
            var colors: [String: String]
        }

        var name: String
        var flavors: [FlavorEntry]
    }

    /// Strict both ways: every ColorToken must be present, and nothing else may be.
    public static func decode(_ data: Data) throws(ThemeFileError) -> Theme {
        let file: File
        do { file = try JSONDecoder().decode(File.self, from: data) } catch { throw .undecodable(String(describing: error)) }
        var flavors: [Flavor] = []
        for entry in file.flavors {
            if let unknown = entry.colors.keys.sorted().first(where: { ColorToken(rawValue: $0) == nil }) {
                throw .unknownToken(flavor: entry.name, token: unknown)
            }
            var colors: [ColorToken: ThemeColor] = [:]
            for token in ColorToken.allCases {
                guard let hex = entry.colors[token.rawValue] else { throw .missingToken(flavor: entry.name, token: token.rawValue) }
                guard let color = ThemeColor(hex: hex) else { throw .badColor(flavor: entry.name, token: token.rawValue, value: hex) }
                colors[token] = color
            }
            flavors.append(Flavor(name: entry.name, appearance: entry.appearance, colors: colors))
        }
        return Theme(name: file.name, flavors: flavors)
    }
}

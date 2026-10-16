// swift-tools-version: 6.2
import PackageDescription

// RaccoonDomain ← RaccoonData ← Raccoon. Each target depends only on the ones to its left.
let package = Package(
    name: "Raccoon",
    platforms: [.macOS(.v15)],
    targets: [
        .target(name: "RaccoonDomain"),
        .target(name: "RaccoonData", dependencies: ["RaccoonDomain"]),
        // The ports' test implementations (§9). Test targets only: no fake ships in the app.
        .target(name: "RaccoonTesting", dependencies: ["RaccoonDomain"]),
        .executableTarget(
            name: "Raccoon",
            dependencies: ["RaccoonDomain", "RaccoonData"],
            // A symlink to design/ui/themes/catppuccin.json, which build.py writes: one copy.
            resources: [.copy("Resources/catppuccin.json")],
            swiftSettings: [.defaultIsolation(MainActor.self)]
        ),
        .testTarget(name: "RaccoonDomainTests", dependencies: ["RaccoonDomain", "RaccoonTesting"]),
        .testTarget(name: "RaccoonDataTests", dependencies: ["RaccoonData", "RaccoonTesting"], resources: [.copy("Fixtures")]),
        .testTarget(name: "RaccoonTests", dependencies: ["Raccoon"]),
    ],
    swiftLanguageModes: [.v6]
)

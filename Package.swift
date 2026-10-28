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
            // Symlinks to design/ui/themes/catppuccin.json and design/ui/assets/empty/, which the
            // two build.py scripts write: one copy each. The app icon is not here: make-app.sh
            // puts it in Raccoon.app as AppIcon.icns.
            resources: [.copy("Resources/catppuccin.json"), .copy("Resources/RaccoonFace@2x.png")],
            swiftSettings: [.defaultIsolation(MainActor.self)]
        ),
        .testTarget(name: "RaccoonDomainTests", dependencies: ["RaccoonDomain", "RaccoonTesting"]),
        .testTarget(name: "RaccoonDataTests", dependencies: ["RaccoonData", "RaccoonTesting"], resources: [.copy("Fixtures")]),
        .testTarget(name: "RaccoonTests", dependencies: ["Raccoon", "RaccoonTesting"]),
    ],
    swiftLanguageModes: [.v6]
)

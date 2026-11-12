// swift-tools-version: 6.2
import PackageDescription

// RaccoonDomain ← RaccoonData ← Raccoon. Each target depends only on the ones to its left.
let package = Package(
    name: "Raccoon",
    platforms: [.macOS(.v15)],
    // The one third-party package, linked by Raccoon alone (DESIGN.md, environment-facts.md).
    dependencies: [.package(url: "https://github.com/airbnb/lottie-ios.git", exact: "4.6.1")],
    targets: [
        .target(name: "RaccoonDomain"),
        .target(name: "RaccoonData", dependencies: ["RaccoonDomain"]),
        // The ports' test implementations (§9). Test targets only: no fake ships in the app.
        .target(name: "RaccoonTesting", dependencies: ["RaccoonDomain"]),
        .executableTarget(
            name: "Raccoon",
            dependencies: ["RaccoonDomain", "RaccoonData", .product(name: "Lottie", package: "lottie-ios")],
            // Symlinks to design/ui/themes/catppuccin.json, design/ui/assets/empty/ and
            // design/ui/assets/loading/, which are written by the two build.py scripts and by hand:
            // one copy each. The app icon is not here: make-app.sh puts it in Raccoon.app as
            // AppIcon.icns.
            resources: [
                .copy("Resources/catppuccin.json"), .copy("Resources/RaccoonFace@2x.png"),
                .copy("Resources/raccoon-rocket.json"),
            ],
            swiftSettings: [.defaultIsolation(MainActor.self)]
        ),
        .testTarget(name: "RaccoonDomainTests", dependencies: ["RaccoonDomain", "RaccoonTesting"]),
        .testTarget(name: "RaccoonDataTests", dependencies: ["RaccoonData", "RaccoonTesting"], resources: [.copy("Fixtures")]),
        .testTarget(
            name: "RaccoonTests",
            dependencies: ["Raccoon", "RaccoonTesting", .product(name: "Lottie", package: "lottie-ios")]
        ),
    ],
    swiftLanguageModes: [.v6]
)

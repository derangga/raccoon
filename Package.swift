// swift-tools-version: 6.2
import PackageDescription

// RaccoonDomain ← RaccoonData ← Raccoon. Each target depends only on the ones to its left.
let package = Package(
    name: "Raccoon",
    platforms: [.macOS(.v15)],
    targets: [
        .target(name: "RaccoonDomain"),
        .target(name: "RaccoonData", dependencies: ["RaccoonDomain"]),
        .executableTarget(
            name: "Raccoon",
            dependencies: ["RaccoonDomain", "RaccoonData"],
            swiftSettings: [.defaultIsolation(MainActor.self)]
        ),
        .testTarget(name: "RaccoonDomainTests", dependencies: ["RaccoonDomain"]),
        .testTarget(name: "RaccoonDataTests", dependencies: ["RaccoonData"]),
        .testTarget(name: "RaccoonTests", dependencies: ["Raccoon"]),
    ],
    swiftLanguageModes: [.v6]
)

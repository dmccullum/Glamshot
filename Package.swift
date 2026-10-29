// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Glamshot",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "GlamshotCore", targets: ["GlamshotCore"]),
        .executable(name: "Glamshot", targets: ["Glamshot"])
    ],
    dependencies: [
        // The family's shared package, checked out next to this repository.
        .package(path: "../DMKit"),
        // Undertone's gradient renderer, for canvas and desktop backgrounds.
        .package(path: "../Undertone")
    ],
    targets: [
        // Value types and layout math, usable from any isolation (App Intents entities need that).
        // PagePhotographer is marked @MainActor itself.
        .target(name: "GlamshotCore"),
        .executableTarget(
            name: "Glamshot",
            dependencies: [
                "GlamshotCore",
                .product(name: "DMKit", package: "DMKit"),
                .product(name: "UndertoneKit", package: "Undertone")
            ],
            swiftSettings: [.defaultIsolation(MainActor.self)]
        ),
        .testTarget(
            name: "GlamshotCoreTests",
            dependencies: ["GlamshotCore"],
            swiftSettings: [.defaultIsolation(MainActor.self)]
        )
    ],
    swiftLanguageModes: [.v6]
)

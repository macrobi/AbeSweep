// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AbeSweep",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "AbeSweep", targets: ["AbeSweep"])
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.9.0")
    ],
    targets: [
        .executableTarget(
            name: "AbeSweep",
            dependencies: [
                .product(name: "Sparkle", package: "Sparkle")
            ],
            path: "Sources/DeepSweep",
            linkerSettings: [
                .unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])
            ]
        ),
        .testTarget(
            name: "AbeSweepTests",
            dependencies: ["AbeSweep"],
            path: "Tests/DeepSweepTests"
        )
    ]
)

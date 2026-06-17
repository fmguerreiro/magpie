// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Magpie",
    platforms: [.macOS(.v13)],
    targets: [
        .target(
            name: "MagpieCore",
            path: "Sources/MagpieCore"
        ),
        .executableTarget(
            name: "Magpie",
            dependencies: ["MagpieCore"],
            path: "Sources/Magpie"
        ),
        .testTarget(
            name: "MagpieCoreTests",
            dependencies: ["MagpieCore"],
            path: "Tests/MagpieCoreTests"
        )
    ]
)

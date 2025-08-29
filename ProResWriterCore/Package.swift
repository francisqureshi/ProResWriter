// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "ProResWriterCore",
    platforms: [
        .macOS(.v14)  // Minimum macOS version for AVFoundation async export APIs
    ],
    products: [
        // Main Core library for media processing (includes TUI components)
        .library(
            name: "ProResWriterCore",
            targets: ["ProResWriterCore"]
        )
    ],
    dependencies: [
        // SwiftFFmpeg for media analysis and processing
        .package(url: "https://github.com/sunlubo/SwiftFFmpeg", from: "1.6.0"),
        // TimecodeKit for professional timecode calculations
        .package(url: "https://github.com/orchetect/TimecodeKit", from: "2.3.3"),
    ],
    targets: [
        // Core media processing engine (includes TUI components)
        .target(
            name: "ProResWriterCore",
            dependencies: [
                "SwiftFFmpeg",
                .product(name: "TimecodeKit", package: "TimecodeKit"),
                .product(name: "TimecodeKitAV", package: "TimecodeKit"),
            ],
            path: "Sources/ProResWriterCore",
            resources: [
                .process("Resources/Fonts/FiraCodeNerdFont-Regular.ttf")
            ]
        ),
        // Unit tests for Core functionality
        .testTarget(
            name: "ProResWriterCoreTests",
            dependencies: ["ProResWriterCore"],
            path: "Tests/ProResWriterCoreTests"
        ),
    ]
)

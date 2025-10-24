// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "SourcePrintCore",
    platforms: [
        .macOS(.v14)  // Minimum macOS version for AVFoundation async export APIs
    ],
    products: [
        // Main Core library for media processing (includes TUI components)
        .library(
            name: "SourcePrintCore",
            targets: ["SourcePrintCore"]
        ),
        // Test executable for diagnosing SwiftFFmpeg frame rate issues
        .executable(
            name: "FrameRateTest",
            targets: ["FrameRateTest"]
        )
    ],
    dependencies: [
        // SwiftFFmpeg for media analysis and processing
        .package(url: "https://github.com/sunlubo/SwiftFFmpeg", from: "1.6.0"),
        // TimecodeKit for professional timecode calculations
        .package(url: "https://github.com/orchetect/TimecodeKit", from: "2.3.3"),
        // FileMonitor for safe file system event monitoring
        .package(url: "https://github.com/aus-der-Technik/FileMonitor.git", from: "1.0.0"),
    ],
    targets: [
        // Core media processing engine (includes TUI components)
        .target(
            name: "SourcePrintCore",
            dependencies: [
                "SwiftFFmpeg",
                .product(name: "TimecodeKit", package: "TimecodeKit"),
                .product(name: "TimecodeKitAV", package: "TimecodeKit"),
                .product(name: "FileMonitor", package: "FileMonitor"),
            ],
            path: "Sources/SourcePrintCore",
            resources: [
                .process("Resources/Fonts/FiraCodeNerdFont-Regular.ttf")
            ]
        ),
        // Test executable for diagnosing SwiftFFmpeg issues
        .executableTarget(
            name: "FrameRateTest",
            dependencies: [
                "SwiftFFmpeg"
            ],
            path: "Sources/FrameRateTest"
        ),
        // Unit tests for Core functionality
        .testTarget(
            name: "SourcePrintCoreTests",
            dependencies: ["SourcePrintCore"],
            path: "Tests/SourcePrintCoreTests"
        ),
    ]
)

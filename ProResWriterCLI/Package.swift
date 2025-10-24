// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "ProResWriterCLI",
    platforms: [
        .macOS(.v14)  // Match SourcePrintCore platform requirements
    ],
    products: [
        // CLI executable
        .executable(
            name: "prores-writer",
            targets: ["ProResWriterCLI"]
        ),
    ],
    dependencies: [
        // Local SourcePrintCore package
        .package(path: "../SourcePrintCore"),
        // Direct dependencies for CLI-specific functionality
        .package(url: "https://github.com/orchetect/TimecodeKit", from: "2.3.3"),
    ],
    targets: [
        // CLI executable target
        .executableTarget(
            name: "ProResWriterCLI",
            dependencies: [
                "SourcePrintCore",
                .product(name: "TimecodeKit", package: "TimecodeKit"),
                .product(name: "TimecodeKitAV", package: "TimecodeKit"),
            ],
            path: "Sources/ProResWriterCLI"
        ),
    ]
)
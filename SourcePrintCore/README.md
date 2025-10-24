# ProResWriterCore

Professional post-production workflow automation core library for macOS.

## Overview

ProResWriterCore provides a complete media processing pipeline for professional video workflows:

- **Import**: Analyze OCF files and graded segments with comprehensive metadata extraction
- **Linking**: Intelligently match segments to original camera files using timecode analysis  
- **BlankRush**: Generate ProRes 4444 blank rushes with timecode burn-in for review
- **PrintProcess**: Create frame-accurate final compositions with broadcast-standard quality

## Key Features

- ✅ Professional frame rate support (23.976, 24, 25, 29.97, 30, 50, 59.94, 60fps with DF/NDF)
- ✅ TimecodeKit integration for broadcast-accurate timecode calculations
- ✅ VideoToolbox hardware acceleration for maximum performance
- ✅ SwiftFFmpeg integration for comprehensive media format support
- ✅ ProRes 4444 quality preservation throughout the workflow

## Usage

### Basic Import Workflow

```swift
import ProResWriterCore

let importer = ImportProcess()

// Import original camera files
let ocfFiles = try await importer.importOriginalCameraFiles(from: ocfDirectoryURL)

// Import graded segments  
let segments = try await importer.importGradedSegments(from: segmentsDirectoryURL)
```

### Media Analysis

```swift
let analyzer = MediaAnalyzer()
let mediaInfo = try await analyzer.analyzeMediaFile(at: fileURL, type: .originalCameraFile)

print("Resolution: \(mediaInfo.resolution)")
print("Frame Rate: \(mediaInfo.frameRate)")  
print("Timecode: \(mediaInfo.sourceTimecode)")
```

## Requirements

- macOS 12.0+
- Xcode 14.0+
- Swift 5.9+

## Dependencies

- [SwiftFFmpeg](https://github.com/sunlubo/SwiftFFmpeg) - Media analysis and processing
- [TimecodeKit](https://github.com/orchetect/TimecodeKit) - Professional timecode calculations

## Installation

### Swift Package Manager

Add ProResWriterCore to your project's Package.swift:

```swift
dependencies: [
    .package(path: "./ProResWriterCore")
]
```

## License

ProResWriterCore is available for professional post-production use.
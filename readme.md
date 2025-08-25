# ProResWriter

Professional video post-production workflow automation tool for matching graded segments with original camera files (OCF) and creating broadcast-ready outputs.

## Overview

ProResWriter streamlines the post-production workflow by:
- **Importing** and analyzing media files with professional frame rate support
- **Linking** graded segments to their original camera files using timecode and metadata matching
- **Creating** blank rush proxies with timecode burn-in for review
- **Compositing** final outputs with frame-accurate positioning

## Core Features

### Import System
- Professional media analysis supporting all broadcast standards (23.976-120fps)
- Accurate frame counting for MXF, MOV, MP4 formats
- Drop-frame and non-drop-frame timecode detection
- Resolution and sample aspect ratio analysis

### Linking System  
- Intelligent parent-child OCF matching using:
  - Filename patterns and reel names
  - Timecode range validation
  - Resolution and frame rate matching
  - Confidence scoring system

### Blank Rush Creation
- Hardware-accelerated VideoToolbox ProRes encoding
- Professional timecode burn-in with TimecodeKit precision
- Source-matching frame rates and resolutions
- Broadcast-standard color space metadata (ITU-R BT.709)

### Print Process
- Frame-accurate composition using AVMutableComposition
- Professional timecode positioning with zero offset
- Segment insertion with proper timing rescaling

## Architecture

```
ProResWriter/
├── Core/                    # Core processing engine
│   ├── Import/             # Media analysis and metadata extraction
│   ├── Linking/            # OCF-segment matching algorithms  
│   ├── BlankRush/          # Proxy generation with timecode burn-in
│   ├── PrintProcess/       # Final composition and output
│   ├── Utilities/          # SMPTE timecode utilities
│   └── TUI/               # Terminal UI components
├── Models/                 # [Future] Project data models
├── UI/                     # [Future] SwiftUI interface
└── Projects/               # [Future] Project management
```

## Professional Standards Supported

- **Film/Cinema**: 23.976fps, 24fps, 48fps, 96fps
- **PAL/European**: 25fps, 50fps, 100fps  
- **NTSC/American**: 29.97fps (DF/non-DF), 59.94fps (DF/non-DF)
- **High Frame Rate**: 90fps, 119.88fps, 120fps

## Build Requirements

- macOS with Xcode
- SwiftFFmpeg framework
- TimecodeKit 2.3.3+
- VideoToolbox (hardware acceleration)

Build with: `./build.sh`

## UI Design

### Interface Architecture
- **Sidebar**: Finder-like project navigation with recent projects
- **Main View**: Three-tab workflow management
  - **Project Tab**: Hierarchical table showing OCF clips with child segments
  - **Media Tab**: Import management with separate OCF/segment tables  
  - **Pairing Tab**: Manual linking controls and confidence review

### Key Features
- **Hierarchical Display**: OCF parents with expandable segment children
- **Status Tracking**: Visual indicators for blank rush generation and link confidence
- **Drag-and-Drop Import**: Direct media file analysis and import
- **Manual Override**: Visual pairing controls when automatic linking needs adjustment

### Example Project View
```
C20250825_0303 {🟢} - 4480x3096 - 23.976fps - 12:25:29:19→12:25:45:04
 ├── C20250825_0303_S001 - Segment metadata - Timecode range
 ├── C20250825_0303_S002 - Segment metadata - Timecode range  
 └── C20250825_0303_S003 - Segment metadata - Timecode range
C20250825_0304 {⚫️} - 4480x3096 - 23.976fps - 12:25:45:05→12:26:08:12
 └── C20250825_0304_S001 - Segment metadata - Timecode range
```

## Status

✅ **Core Engine Complete** - Professional-grade media processing pipeline operational  
🚧 **UI Development** - SwiftUI interface and project management design finalized, implementation in progress
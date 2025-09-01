## Build Instructions

- Build with `@build.sh` for CLI, let me handle building/running for error reporting
- Build GUI with `build-sourceprint.sh` 

## Core Architecture (Current Status)

### ProResWriter Package Structure
```
ProResWriter/
├── ProResWriterCore/              # Swift Package Library
├── ProResWriterCLI/               # Executable Package  
└── SourcePrint/                   # macOS App Project
    └── SourcePrint/Features/      # Feature-based SwiftUI organization
        ├── MediaImport/
        ├── Linking/ 
        ├── Render/
        ├── Overview/
        └── ProjectManagement/
```

### Current Technical Stack
- **ProRes 4444 Pipeline**: VideoToolbox hardware-accelerated encoding throughout
- **TimecodeKit Integration**: Frame-accurate calculations for all professional frame rates
- **Swift Package Architecture**: Shared Core engine between CLI and GUI
- **Feature-Based UI**: Modular SwiftUI components (ContentView.swift: 1276→51 lines)

## Working Components ✅

### Core Processing Engine
- **Import**: Media analysis with parallel processing, recursive directory support
- **Linking**: OCF-segment matching with confidence scoring using TimecodeKit precision
- **Blank Rush**: ProRes 4444 generation with running timecode burn-in (180-240fps)
- **Print Process**: Final composition with passthrough quality preservation

### Filter Graph Pipeline (Black Frame + Timecode)
```swift
// Generates exact frame count with running timecode
color=black:size=4480x3096:duration=23.565:rate=24000/1001
timecode='12:25:29:19':timecode_rate=24000/1001:fontcolor=white:fontsize=64:x=50:y=150
pix_fmts=uyvy422
```

### Professional Frame Rate Support
- **Film**: 23.976fps, 24fps, 47.952fps, 48fps ✅ TESTED  
- **PAL**: 25fps, 50fps ✅ TESTED
- **NTSC**: 29.97fps, 59.94fps (DF/non-DF) ✅ TESTED
- **HD**: 30fps, 60fps, 90fps, 120fps
- **Ultra**: 95.904fps, 96fps, 100fps, 119.88fps

### SourcePrint GUI Application
- **Project Management**: .w2 JSON files with auto-save, sidebar navigation
- **Media Import**: 4 modes (single/multiple files/folders) with multithreaded analysis
- **Real-Time Progress**: Frame-accurate encoding feedback with FPS display
- **Professional Metadata**: Frame counts, timecode ranges, resolution, confidence indicators
- **Status Indicators**: 🟢🟡⚫️🔴 for workflow state tracking

## Key Technical Achievements

### Performance Optimizations
- **Multithreaded Import**: 3-4 seconds vs 24 seconds (12 files)
- **Hardware Acceleration**: VideoToolbox ProRes 4444 at 180-240fps
- **Frame-Accurate Processing**: TimecodeKit eliminates floating-point errors
- **Dual Progress Systems**: TUI for CLI, async callbacks for GUI

### Professional Standards  
- **Color Space**: Broadcast BT.709 (16-235 range) for DaVinci Resolve compatibility
- **Timecode Precision**: Zero-frame offset using TimecodeKit algorithms
- **Quality Pipeline**: ProRes 4444 throughout, passthrough final export
- **Frame Count Accuracy**: Direct MediaFileInfo integration vs duration calculation

## Architecture Benefits

- **Code Reusability**: ProResWriterCore shared between CLI/GUI
- **Maintainability**: Feature-based organization, clean separation of concerns  
- **Professional UX**: Interface patterns matching post-production workflows
- **Team Development**: Modular components enable parallel development
- **Testing**: Independent component testing with SwiftUI Canvas previews

## Production Ready Status 🎬

**Complete professional post-production workflow:**
1. Project creation with native directory pickers
2. Media import (4 modes) with parallel processing  
3. OCF-segment linking with confidence scoring
4. ProRes 4444 blank rush generation with progress tracking
5. Final composition with passthrough quality preservation

**Performance tested and verified for professional broadcast workflows.**
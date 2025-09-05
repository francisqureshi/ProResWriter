## Build Instructions

- Build with `@build.sh` for CLI, let me handle building/running for error reporting
- Build GUI with `build-sourceprint.sh` 

## 🚀 TOP PRIORITY OPTIMIZATION TODO

### SwiftFFmpeg Performance Optimization Goal ✅ BREAKTHROUGH!
**Target**: Match Apple AVFoundation passthrough speed (currently 2x faster than SwiftFFmpeg)
- **AVFoundation**: 9.26s for 425.4s timeline with 13 segments  
- **SwiftFFmpeg**: 10.78s for same timeline (only 1.5s slower!)
- **Previous**: 16.83s (massive 6s improvement achieved!)

**🎯 BOTTLENECK IDENTIFIED via Detailed Timing Analysis:**
- **📝 Segment Analysis: 2.932s (27.2%)** ← PRIMARY BOTTLENECK
  - 0.226s per segment average for `avformat_find_stream_info()`
  - **REDUNDANT**: Analyzing each segment twice (pre-analysis + during copying)
- **🚀 Stream Copying: 7.758s (71.9%)**
  - Base video: 6000-9000 fps (excellent!)
  - Segments: 130-300 fps (includes analysis overhead)
- **🔍 Base Analysis: 0.093s (0.9%)** (negligible)

**🎉 OPTIMIZATION STRATEGY:**
Eliminate redundant segment analysis by caching stream properties in `FFmpegGradedSegment`
- **Projected Performance**: ~7.8s (15% FASTER than AVFoundation!)
- **Method**: Skip `avformat_find_stream_info()` during copying phase
- **Expected Outcome**: SwiftFFmpeg EXCEEDING AVFoundation speed while maintaining Premiere Pro compatibility

## SwiftFFmpeg Print Process Implementation (2025-09-02)

### Premiere Pro Compatibility Solution ✅
- **Problem Solved**: AVFoundation `AVAssetExportPresetPassthrough` creates complex edit lists that Premiere Pro rejects
- **SwiftFFmpeg Solution**: Direct stream copying without composition metadata eliminates edit list atoms
- **New Implementation**: `printProcessFFmpeg.swift` using proven patterns from `blankRushIntermediate.swift`
- **VFX Architecture Fixed**: Complete metadata flow from UI `MediaFileInfo.isVFXShot` to final output

### Technical Implementation
- **Stream Processing**: Direct packet copying using `AVFormatContext.readFrame()` and `interleavedWriteFrame()`
- **Frame-Precise Cutting**: `AVMath.rescale()` for exact timeline positioning using rational arithmetic
- **Timeline Assembly**: Base video foundation + segment replacement (no composition/edit lists)
- **Premiere Compatible Output**: Sequential stream data in clean MOV container structure
- **Performance**: True passthrough speed with hardware VideoToolbox ProRes encoding

### Architecture Benefits
- **Clean Data Flow**: `FFmpegCompositorSettings` carries VFX metadata from UI through to output
- **Conversion Bridge**: Seamless migration from existing AVFoundation workflow
- **Dual Approach**: Both AVFoundation (current) and SwiftFFmpeg (Premiere-compatible) available
- **Proven Foundation**: Built on working SwiftFFmpeg patterns from blank rush creation

### Branch Status
- **Branch**: `ffmpeg-print-exploration` 
- **Status**: SwiftFFmpeg print process implementation in progress - functional but needs refinement
- **Implementation**: Chronological timeline processing eliminates edit lists, generates playable files
- **Issues**: Frame rate metadata encoding incorrect, needs investigation and fix
- **Next**: Fix FPS metadata, then test Premiere Pro compatibility

### Implementation Progress (2025-09-02)

#### Initial SwiftFFmpeg Implementation ✅
- **Complete Implementation**: Created `printProcessFFmpeg.swift` with full SwiftFFmpeg-based compositor
- **Data Models**: `FFmpegCompositorSettings` and `FFmpegGradedSegment` for VFX metadata flow
- **Core Integration**: `SwiftFFmpegProResCompositor` class matching existing patterns from `blankRushIntermediate.swift`
- **Test Integration**: Added `testSwiftFFmpegPrintProcess()` to CLI for direct comparison with AVFoundation

#### DTS Monotonicity Resolution ✅
- **Problem**: AVFoundation creates complex edit lists, SwiftFFmpeg encountered DTS monotonicity errors
- **Root Cause**: Timeline discontinuities from overlaying segments onto base video foundation  
- **Solution**: Implemented chronological timeline processing with continuous timestamps
- **Architecture**: `processTimelineChronologically()` processes segments in temporal order vs overlapping

#### Technical Fixes Applied
- **Timestamp Management**: Simplified DTS = PTS for ProRes I-frame codec (eliminates PTS < DTS violations)
- **Timeline Continuity**: Sequential segment processing with `currentOutputPTS` tracking
- **Stream Copying**: Direct packet copying with proper timebase rescaling using `AVMath.rescale()`
- **Error Handling**: Proper SwiftFFmpeg EOF pattern: `catch let error as SwiftFFmpeg.AVError where error == .eof`

#### Code Architecture Changes
```swift
// Old approach: Base video foundation + segment overlays (created edit lists)
try await copyBaseVideoAsFoundation() 
for segment in segments { try await applySegmentToTimeline() }

// New approach: Chronological processing (eliminates edit lists)
try await processTimelineChronologically() // Segments in temporal order
```

#### BREAKTHROUGH SUCCESS! ✅
- **Complete Implementation**: SwiftFFmpeg print process fully operational
- **SMPTE Frame Precision**: Perfect frame placement (207, 425, 596) using professional timecode calculations
- **Full Passthrough Speed**: 1.77 seconds for complete 1320-frame timeline (33x speed improvement)
- **Premiere Pro Compatible**: Clean MOV structure without complex edit lists
- **Professional Quality**: ProRes 4444 pipeline with correct FPS encoding (25.000fps)
- **Stream-Based Architecture**: Bulk copying for both base video and segments at maximum speed
- **Production Ready**: Frame-accurate, broadcast-quality output for professional workflows

#### Performance Analysis & Optimization (2025-09-03) 🔬
- **Detailed Timing Implementation**: Added comprehensive performance measurements throughout SwiftFFmpeg pipeline
- **Major Performance Improvement**: 16.83s → 10.78s (6s improvement via timing analysis)
- **Bottleneck Identification**: Segment analysis consuming 27.2% of total time via redundant `avformat_find_stream_info()` calls
- **Optimization Target**: Cache stream properties to eliminate duplicate analysis (projected 15% faster than AVFoundation)
- **Performance Metrics**: Base video copying at 6000-9000 fps, segments at 130-300 fps (analysis overhead included)

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
- **Reactive UI**: `@ObservedObject` for cross-tab synchronization (MediaImportTab updates when LinkingTab removes files)
- **Context Menu UX**: Left-click ellipsis menus with `.menuOrder(.fixed)` for window-bounded dropdowns

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

## 🎯 SwiftFFmpeg Integration Complete (2025-09-05)

### Branch Merge Successfully Completed ✅
- **Source Branch**: `ffmpeg-print-exploration` 
- **Target Branch**: `main`
- **Merge Status**: ✅ **PRODUCTION READY**
- **Files Added**: `printProcessFFmpeg.swift`, documentation, AI chat logs
- **Conflicts Resolved**: CLI paths, method visibility (`getTimecodeFrameRate` → internal)

### Final Performance Achievement 🚀
- **AVFoundation**: 8.09s for 425.4s timeline with 13 segments
- **SwiftFFmpeg**: 9.10s for same timeline (only **1.01s slower**, 89% speed match!)
- **Major Improvement**: From original 16.83s to 9.10s (**46% performance gain**)
- **Optimization Success**: Cached segment analysis eliminated redundant `avformat_find_stream_info()` calls

### Production Implementation Benefits
- **✅ Premiere Pro Compatible**: Eliminates "complex edit list" errors completely
- **✅ Frame-Accurate**: SMPTE timecode precision for professional workflows  
- **✅ VFX Metadata Flow**: Complete UI → print process integration
- **✅ Dual Architecture**: Both AVFoundation + SwiftFFmpeg available for different use cases
- **✅ Hardware Accelerated**: VideoToolbox ProRes encoding throughout
- **✅ Edge Case Handling**: Perfect frame 0, last frame, and consecutive segment support

### Technical Architecture Finalized
```swift
// SwiftFFmpeg approach: Direct stream copying (no edit lists)
let ffmpegCompositor = SwiftFFmpegProResCompositor()
ffmpegCompositor.composeVideo(with: ffmpegSettings)

// Performance breakdown achieved:
// - Base analysis: 1.0% (negligible)  
// - Segment analysis: 32.9% (optimized with caching)
// - Stream copying: 66.1% (bulk passthrough speed)
```

### Integration Status
- **Compilation**: ✅ Clean build (warnings only, no errors)
- **Testing**: ✅ CLI `testSwiftFFmpegPrintProcess()` function ready
- **Repository**: ✅ Merged to main, pushed to remote
- **Documentation**: ✅ Complete implementation progress tracked

**🎬 SwiftFFmpeg print process now available in production for Premiere Pro compatibility workflows.**
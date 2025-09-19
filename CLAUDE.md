## Build Instructions

- Build with `@build.sh` for CLI, let me handle building/running for error reporting
- Build GUI with `build-sourceprint.sh`

## 🎯 TOP PRIORITY TODOS

### Frame Ownership Analysis System ✅ **COMPLETE**
- **✅ Pre-computed Segment Relationships**: Analyze overlaps and priorities at linking stage
  - **✅ Grade Overlap Resolution**: Later segments overwrite earlier ones in overlap zones
  - **✅ VFX Absolute Priority**: VFX shots never overwritten, maintain exact timecode position
  - **✅ Example**: `[Seg1: TC 1001-1200][VFX: TC 1050-1066][Seg2: TC 1100-1300]`
    - Result: `Seg1(1001-1049) → VFX(1050-1066) → Seg1(1067-1099) → Seg2(1100-1200) → Seg2(1201-1300)`
- **✅ Processing Plan Generation**: Convert ownership map to efficient copy ranges for print process
- **✅ PrintProcess Integration**: SwiftFFmpeg now uses ProcessingPlan with segment offset support
- **✅ Linking Workflow Integration**: Frame ownership analysis runs during linking stage
- **⏳ Timeline Visualization Data**: Available for UI timeline preview (pending implementation)

### Code Quality & Data Integrity
- **⏳ Audit Fallback Values**: Search entire codebase for `??` fallback operators that could mask data quality issues in media analysis, video processing, and frame calculations. Replace silent fallbacks with explicit error handling where missing data should fail fast rather than continue with arbitrary default values.

### Architecture Benefits Achieved:
- **✅ Single Computation**: Analysis happens once at linking stage (not repeated each print)
- **✅ Clean Separation**: Analysis logic separate from video processing in `FrameOwnershipAnalyzer.swift`
- **✅ Debugging Support**: Frame ownership inspection with detailed logging
- **✅ VFX Protection**: Frame-by-frame ownership ensures VFX shots are never overwritten
- **✅ Offset Handling**: Partial segment copying with `copySegmentFramesWithOffset` method

### Critical Issues
- **Fix VFX printing**: ✅ **RESOLVED** by Frame Ownership Analysis system
- **UI Preview Timeline**: ✅ **DATA AVAILABLE** for timeline preview (visualization data ready)

### Future Optimizations
- **Remove guessRationalFromFloat**: After Frame Ownership system is complete, ensure all segments always have exact AVRational frame rates from import/linking stage. The guessRationalFromFloat() helper should become unnecessary as we should always know the exact rational (24000/1001 for 23.976, etc.) from the source media analysis.

## SwiftFFmpeg Print Process ✅

**Production Status**: SwiftFFmpeg is the default print process for Premiere Pro compatibility
- **Performance**: 89% of AVFoundation speed with full Premiere Pro compatibility
- **Architecture**: Direct stream copying eliminates edit lists that cause Premiere Pro import errors
- **VFX Support**: Complete metadata flow from UI through to final output

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

## Core Features ✅

### Processing Pipeline
- **Import**: Multithreaded media analysis with recursive directory support (3-4s vs 24s)
- **Linking**: Strict validation-based OCF-segment matching with professional timecode precision
- **Blank Rush**: Hardware-accelerated ProRes 4444 generation (180-240fps) with running timecode
- **Print Process**: SwiftFFmpeg-based composition with Premiere Pro compatibility

### SourcePrint GUI
- **Project Management**: .w2 JSON files with native macOS File menu integration
- **Professional UI**: Apple Compressor theming, render queue system, status tracking
- **Advanced Features**: Timeline preview, batch operations, modification detection

### Technical Standards
- **Frame Rates**: Full professional support (23.976-120fps, drop frame, etc.)
- **Quality**: ProRes 4444 pipeline, BT.709 color space, SMPTE timecode precision
- **Architecture**: Shared Core library, feature-based organization, reactive UI

## Critical Bug Fixes ✅

### Frame Rate & Timecode Precision
- **Frame Rate Encoding**: Fixed 23.976fps precision using rational arithmetic instead of float calculations
- **Last Frame Accuracy**: Segments ending at timeline boundary now use timecode-based calculation instead of duration
- **SMPTE Support**: Professional drop frame and non-drop frame handling for all frame rates
- **Boundary Handling**: Fixed 59.94 DF clips ending exactly at OCF boundary

## Recent Feature Implementations ✅

### Render Queue System
- **Professional Workflow**: NLE-style queue with batch operations, modification detection, and graceful stop control
- **Status Tracking**: Complete print history with automatic re-print flagging when segments change

### UI/UX Improvements
- **Typography**: SF Pro migration with monospaced digits for stable layouts
- **Linking Rules**: Strict validation-based matching with consumer camera detection and VFX exemptions
- **Apple Compressor Theming**: Professional purple accent with dark backgrounds
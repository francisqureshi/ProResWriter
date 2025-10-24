# SourcePrint

A silly solution to a silly problem, a video post-production tool that composites consolidated graded segments back into blanked out source length original camera files (OCF) with frame-accurate timecode positioning.

## How It Works

Layered composition with frame ownership analysis:

```
┌─────────────────────────────────────────────────────────────────┐
│ Layer 3 (VFX)        │                     ▓▓▓▓▓▓               │
│ Layer 2 (Grades)     │       ███████████           ███████████  │
│ Layer 1 (Rush)       │ ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░  │
├──────────────────────┼──────────────────────────────────────────┤
│ Final Output         │ ░░░░░░████████████░░▓▓▓▓▓▓░░███████████  │
│                      │ ^Rush ^Grade        ^VFX    ^Grade       │
└─────────────────────────────────────────────────────────────────┘

Legend:
  ░░░  Blank rush (timecode burn-in)
  ███  Graded segments (from DaVinci timeline)
  ▓▓▓  VFX shots (absolute priority, never overwritten)
```

## Features

- **Timecode-Based Linking** - Matches graded segments to OCF using SMPTE timecode
- **Frame Ownership Analysis** - Resolves overlaps with VFX absolute priority
- **Blank Rush Generation** - Hardware-accelerated ProRes 4444 with timecode burn-in
- **Professional Standards** - All broadcast frame rates (23.976-120fps, drop/non-drop)

## Build

```bash
# Build static FFmpeg + dependencies (one-time setup)
./build-static-deps.sh
./build-static-ffmpeg.sh

# Build SourcePrint.app
./build-sourceprint.sh
```

## Technical Stack

- **Swift** - Core engine and SwiftUI interface
- **SwiftFFmpeg** - Video processing with static FFmpeg 7.1.2
- **TimecodeKit** - SMPTE timecode calculations
- **VideoToolbox** - Hardware-accelerated ProRes encoding

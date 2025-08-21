## Workflow Techniques

- Adding timecode tracks can be done by using specific methods in video editing workflows

## ProResWriter Transcoding Success (2025-08-20)

### Key Technical Fixes Implemented
- **Frame Count Issue**: Fixed MXF files reporting frameCount=0 by using duration directly for professional timebases (1001/24000, 1001/60000)
- **Framerate Metadata**: Resolved "one frame short" issue by setting `outputVideoStream.averageFramerate = properties.frameRate` 
- **Drop Frame Timecode**: Full support for both DF (semicolon) and non-DF (colon) timecode formats
- **MediaFileInfo-based Transcoding**: Created efficient transcoding that uses pre-analyzed metadata instead of re-extracting

### Working Components
- **Import Process**: Correctly analyzes MXF files with accurate frame counts (565 frames for 23.976fps, 270 frames for 59.94fps DF)
- **Linking Process**: Successfully matches graded segments to OCF parents using timecode range validation
- **Blank Rush Creation**: Uses VideoToolbox ProRes 422 Proxy encoding with perfect frame preservation
- **Professional Timebases**: Handles AVRational framerates (24000/1001) correctly for container timing

### Current Status
- Complete workflow working: Import → Link → Transcode
- All 565 frames preserved in transcoding (no missing frames)
- Drop frame and non-drop frame timecode both supported
- Hardware-accelerated VideoToolbox encoding functional

## Black Frame Generation Filter Success (2025-08-21)

### Filter Graph Pipeline Achievement
- **Synthetic Black Frame Generation**: Successfully created filter graph pipeline generating exact black frames matching source specifications
- **VideoToolbox Integration**: Filter graph outputs `uyvy422` format directly compatible with `prores_videotoolbox` encoder
- **Perfect Frame Count**: Generates exact 565 frames (matching source transcode) using MediaFileInfo `durationInFrames`
- **Professional Timing**: Maintains precise `24000/1001` framerate with proper timebase handling

### Technical Implementation
- **Filter Chain**: `color → format → buffersink` pipeline with pixel format conversion
- **MediaFileInfo Integration**: Uses import process data directly for accurate frame counts instead of duration calculation
- **Hardware Encoding**: VideoToolbox ProRes 422 Proxy with proper timing rescaling
- **Metadata Preservation**: Maintains timecode, framerate, and resolution from source

### Filter Graph Components
```swift
// Color filter: generates black frames at source dimensions and framerate
color=black:size=4480x3096:duration=23.565:rate=24000/1001

// Format filter: converts to VideoToolbox-compatible pixel format
pix_fmts=uyvy422

// Buffersink: outputs frames ready for encoder
```

### Verified Success Metrics
- ✅ **565 frames generated** (exact match with working transcode)
- ✅ **565 packets encoded** (perfect 1:1 ratio)
- ✅ **VideoToolbox ProRes 422 Proxy** encoding successful
- ✅ **Timecode preserved**: `12:25:29:19` (non-drop frame)
- ✅ **Professional framerate**: `24000/1001 = 23.976025fps`
- ✅ **Filter graph pipeline** operational with proper pixel format handling

### Testing Requirements & Professional Frame Rates
**URGENT: Need comprehensive test files for all professional frame rates**

#### Standard Professional Frame Rates to Test:
- **23.976fps** (24000/1001) - Film rate ✅ TESTED
- **24fps** (24/1) - True film rate
- **25fps** (25/1) - PAL standard 
- **29.97fps** (30000/1001) - NTSC standard (often drop frame)
- **30fps** (30/1) - True 30fps
- **50fps** (50/1) - PAL high frame rate
- **59.94fps** (60000/1001) - NTSC high frame rate (often drop frame) ✅ TESTED
- **60fps** (60/1) - True 60fps
- **47.952fps** (48000/1001) - High frame rate film variant
- **48fps** (48/1) - High frame rate film

#### Drop Frame Variants to Test:
- 29.97 DF (semicolon separator)
- 59.94 DF (semicolon separator) ✅ TESTED
- Verify non-DF versions use colon separator

#### Test Coverage Needed:
- MXF files with frameCount=0 for each rate
- MOV/MP4 files with reliable frameCount 
- Various professional codecs (ProRes, DNx, XAVC, etc.)
- Different timecode start points
- Various durations to test frame count accuracy

**Priority**: Gather test material for untested frame rates before production use
- we build with @build.sh but let me do the building and running and ill send you the errors.
- save this filter work  to memory
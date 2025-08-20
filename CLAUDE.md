## Workflow Techniques

- Adding timecode tracks can be done by using specific methods in video editing workflows

## ProResWriter Transcoding Success (2025-08-20)

### Key Technical Fixes Implemented
- **Frame Count Issue**: Fixed MXF files reporting frameCount=0 by using duration directly for professional timebases (1001/24000, 1001/60000)
- **Framerate Metadata**: Resolved "one frame short" issue by setting `outputVideoStream.averageFramerate = properties.frameRate` 
- **Drop Frame Timecode**: Full support for both DF (semicolon) and non-DF (colon) timecode formats
- **MediaFileInfo-based Transcoding**: Created efficient transcoding that uses pre-analyzed metadata instead of re-extracting

### Working Components
- **Import Process**: Correctly analyzes MXF files with accurate frame counts (407 frames for 23.976fps, 270 frames for 59.94fps DF)
- **Linking Process**: Successfully matches graded segments to OCF parents using timecode range validation
- **Blank Rush Creation**: Uses VideoToolbox ProRes 422 Proxy encoding with perfect frame preservation
- **Professional Timebases**: Handles AVRational framerates (24000/1001) correctly for container timing

### Current Status
- Complete workflow working: Import → Link → Transcode
- All 407 frames preserved in transcoding (no missing frames)
- Drop frame and non-drop frame timecode both supported
- Hardware-accelerated VideoToolbox encoding functional

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
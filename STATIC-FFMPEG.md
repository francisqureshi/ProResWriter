# Static FFmpeg Integration for SourcePrint

## Summary

SourcePrint now uses **static FFmpeg 7.1.2 libraries** instead of Homebrew's dynamic libraries. This is a major step toward self-contained distribution.

## What Was Accomplished

### Built Static FFmpeg 7.1.2
- ✅ All 8 FFmpeg libraries built as static (.a files) for Apple Silicon
- ✅ ~126MB total library size
- ✅ Includes all features needed: VideoToolbox, drawtext (freetype), color/format/scale filters
- ✅ Optimized for arm64 with NEON instructions

### SourcePrint Integration
- ✅ No longer depends on Homebrew FFmpeg dynamic libraries
- ✅ FFmpeg code is compiled directly into the SourcePrint binary
- ✅ Custom pkg-config wrapper ensures static libraries are used during build

### Remaining Homebrew Dependencies (7 libraries)
- freetype + libpng (needed for drawtext filter with timecode burn-in)
- liblzma (xz compression)
- libX11, libxcb, libXau, libXdmcp (X11 libraries - likely unnecessary on macOS)

### Before vs After
**Before:**
```
/opt/homebrew/opt/ffmpeg@7/lib/libavformat.61.dylib
/opt/homebrew/opt/ffmpeg@7/lib/libavcodec.61.dylib
/opt/homebrew/opt/ffmpeg@7/lib/libavfilter.10.dylib
/opt/homebrew/opt/ffmpeg@7/lib/libavutil.59.dylib
/opt/homebrew/opt/ffmpeg@7/lib/libswresample.5.dylib
/opt/homebrew/opt/ffmpeg@7/lib/libswscale.8.dylib
```

**After:**
```
🎉 No FFmpeg dynamic libraries - using static FFmpeg!
```

## Build Process

### 1. Build Static FFmpeg (one-time)
```bash
./build-static-ffmpeg.sh
```
Takes 10-15 minutes. Creates:
- `/Users/mac10/Projects/ProResWriter/ffmpeg-build/install/lib/` - Static libraries
- `/Users/mac10/Projects/ProResWriter/ffmpeg-build/install/include/` - Headers

### 2. Build SourcePrint
```bash
./build-sourceprint.sh
```
Uses custom pkg-config wrapper to force static linking.

## Technical Details

### FFmpeg Build Configuration
```bash
./configure \
    --enable-static \
    --disable-shared \
    --enable-gpl \
    --enable-version3 \
    --enable-videotoolbox \
    --enable-libfreetype \
    --arch=arm64 \
    --enable-optimizations \
    --enable-asm \
    --enable-neon \
    --disable-debug \
    --enable-pic
```

### SourcePrint Build Modifications
1. **pkg-config-static.sh** - Wrapper that forces `--static` flag
2. **PKG_CONFIG_PATH override** - Points only to our static FFmpeg (no Homebrew)
3. **Additional linker flags** - Explicitly links libavfilter, libpostproc, freetype, libpng

### Files Created/Modified
- `build-static-ffmpeg.sh` - Builds static FFmpeg from source
- `pkg-config-static.sh` - Custom pkg-config wrapper
- `build-sourceprint.sh` - Updated to use static FFmpeg
- `.gitignore` - Excludes `ffmpeg-build/` directory

## Future Improvements

To make SourcePrint **completely self-contained**, we would need to:

1. **Build static freetype + libpng** (for drawtext filter)
2. **Remove X11 dependencies** (probably not actually used on macOS)
3. **Bundle remaining dynamic libraries** (if any) inside app bundle

Or alternatively:
- Use macOS's Core Text instead of freetype for text rendering
- This would eliminate freetype, libpng, and X11 dependencies entirely

## User Distribution

### Current State
Users still need Homebrew + some libraries:
```bash
brew install freetype libpng xz libx11
```

### Deployment Goal
Eventually distribute SourcePrint.app as a standalone download with zero dependencies.

## Verification

Check if app uses static FFmpeg:
```bash
otool -L ./SourcePrint/build/Build/Products/Release/SourcePrint.app/Contents/MacOS/SourcePrint | grep -E "avcodec|avformat|avutil"
```
Should return nothing (static libraries don't show in otool -L).

Check remaining dependencies:
```bash
otool -L ./SourcePrint/build/Build/Products/Release/SourcePrint.app/Contents/MacOS/SourcePrint | grep /opt/homebrew
```

## Build Time

- **Static FFmpeg build**: 10-15 minutes (one-time)
- **SourcePrint build**: 2-3 minutes (with static FFmpeg)

## Binary Size Impact

Static linking increases the SourcePrint binary size by ~40MB (FFmpeg code is now embedded in the app).

This is acceptable tradeoff for eliminating 6 FFmpeg dynamic library dependencies.

---

**Status**: ✅ Static FFmpeg integration complete!
**Next step**: Optional - eliminate remaining Homebrew dependencies (freetype, libpng, X11)

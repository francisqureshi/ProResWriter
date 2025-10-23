#!/bin/bash

# Bundle FFmpeg libraries into SourcePrint.app
# This makes the app self-contained and distributable

set -e

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

APP_PATH="SourcePrint/build/Build/Products/Release/SourcePrint.app"
FRAMEWORKS_DIR="$APP_PATH/Contents/Frameworks"
FFMPEG_SOURCE="/opt/homebrew/opt/ffmpeg@7/lib"

echo -e "${BLUE}📦 Bundling FFmpeg 7.1.2 into SourcePrint.app${NC}"

# Check if app exists
if [ ! -d "$APP_PATH" ]; then
    echo -e "${RED}❌ App not found at $APP_PATH${NC}"
    echo "Please run ./build-sourceprint.sh first"
    exit 1
fi

# Create Frameworks directory if it doesn't exist
mkdir -p "$FRAMEWORKS_DIR"

# List of FFmpeg libraries to bundle
FFMPEG_LIBS=(
    "libavcodec.61.19.101.dylib"
    "libavdevice.61.3.100.dylib"
    "libavfilter.10.4.100.dylib"
    "libavformat.61.7.100.dylib"
    "libavutil.59.39.100.dylib"
    "libpostproc.58.3.100.dylib"
    "libswresample.5.3.100.dylib"
    "libswscale.8.3.100.dylib"
)

echo -e "${BLUE}Copying FFmpeg libraries...${NC}"
for lib in "${FFMPEG_LIBS[@]}"; do
    if [ -f "$FFMPEG_SOURCE/$lib" ]; then
        cp -f "$FFMPEG_SOURCE/$lib" "$FRAMEWORKS_DIR/"
        chmod u+w "$FRAMEWORKS_DIR/$lib"  # Make writable for install_name_tool
        echo "  ✓ $lib"
    else
        echo -e "${RED}  ✗ $lib not found!${NC}"
        exit 1
    fi
done

echo -e "${BLUE}Fixing library install names...${NC}"

# Fix install names to use @rpath
for lib in "${FFMPEG_LIBS[@]}"; do
    LIB_PATH="$FRAMEWORKS_DIR/$lib"

    # Change the library's own install name
    install_name_tool -id "@rpath/$lib" "$LIB_PATH" 2>/dev/null

    # Fix all Homebrew FFmpeg paths to use @rpath
    # Get all dependencies from this library
    deps=$(otool -L "$LIB_PATH" | grep -E "(ffmpeg@7|Cellar/ffmpeg)" | awk '{print $1}')

    for dep_path in $deps; do
        # Extract just the library filename from the path
        dep_name=$(basename "$dep_path")

        # Find the matching full versioned name from our FFMPEG_LIBS array
        for versioned_lib in "${FFMPEG_LIBS[@]}"; do
            # Check if this versioned lib matches (handles symlinks like libavcodec.61.dylib -> libavcodec.61.19.101.dylib)
            if [[ "$versioned_lib" == "$dep_name"* ]] || [[ "$dep_name" == "${versioned_lib%.*.*.*}.dylib" ]] || [[ "$dep_name" == "${versioned_lib%.*.*}.dylib" ]] || [[ "$dep_name" == "${versioned_lib%.*}.dylib" ]]; then
                install_name_tool -change "$dep_path" "@rpath/$versioned_lib" "$LIB_PATH" 2>/dev/null
                break
            fi
        done
    done

    # Re-sign the library (adhoc signature)
    codesign --force --sign - "$LIB_PATH" 2>/dev/null
    echo "  ✓ $lib"
done

echo -e "${BLUE}Fixing main executable...${NC}"

# Fix the main executable to use @rpath
EXECUTABLE="$APP_PATH/Contents/MacOS/SourcePrint"

deps=$(otool -L "$EXECUTABLE" | grep -E "(ffmpeg@7|Cellar/ffmpeg)" | awk '{print $1}')

for dep_path in $deps; do
    dep_name=$(basename "$dep_path")

    # Find the matching full versioned name from our FFMPEG_LIBS array
    for versioned_lib in "${FFMPEG_LIBS[@]}"; do
        if [[ "$versioned_lib" == "$dep_name"* ]] || [[ "$dep_name" == "${versioned_lib%.*.*.*}.dylib" ]] || [[ "$dep_name" == "${versioned_lib%.*.*}.dylib" ]] || [[ "$dep_name" == "${versioned_lib%.*}.dylib" ]]; then
            install_name_tool -change "$dep_path" "@rpath/$versioned_lib" "$EXECUTABLE" 2>/dev/null
            echo "  ✓ Fixed $dep_name → @rpath/$versioned_lib"
            break
        fi
    done
done

# Re-sign the main executable
codesign --force --sign - "$EXECUTABLE" 2>/dev/null

echo -e "${GREEN}✅ FFmpeg 7.1.2 bundled successfully!${NC}"
echo ""
echo "Libraries installed in:"
echo "  $FRAMEWORKS_DIR"
echo ""
echo "Total size:"
du -sh "$FRAMEWORKS_DIR" 2>/dev/null | awk '{print "  " $1}' || echo "  ~16MB"

#!/bin/bash

# SourcePrint macOS App Build Script with Static FFmpeg
# Forces static linking by overriding pkg-config

set -e

# Check for static build (FFmpeg + dependencies)
STATIC_BUILD_DIR="$PWD/static-build/install"

if [ ! -d "$STATIC_BUILD_DIR" ]; then
    echo "❌ Static FFmpeg and dependencies not found at $STATIC_BUILD_DIR"
    echo "Run: ./build-static-deps.sh && ./build-static-ffmpeg.sh"
    exit 1
fi

# Check for Homebrew FFmpeg (needed for SwiftFFmpeg compilation headers)
HOMEBREW_FFMPEG="/opt/homebrew/opt/ffmpeg@7"
if [ ! -d "$HOMEBREW_FFMPEG" ]; then
    echo "❌ Homebrew FFmpeg not found (required for SwiftFFmpeg compilation)"
    echo "   SwiftFFmpeg needs FFmpeg headers at compile time, even when linking statically"
    echo "Run: brew install ffmpeg@7"
    exit 1
fi

# Use our custom pkg-config wrapper (cleaner than PATH manipulation)
chmod +x "$PWD/pkg-config-static.sh"
export PKG_CONFIG="$PWD/pkg-config-static.sh"

# Force pkg-config to ONLY use our static build
export PKG_CONFIG_PATH="$STATIC_BUILD_DIR/lib/pkgconfig"
export PKG_CONFIG_LIBDIR="$STATIC_BUILD_DIR/lib/pkgconfig"

echo "🔨 Building SourcePrint with static FFmpeg..."
echo "   Static libraries: $STATIC_BUILD_DIR/lib"
echo "   pkg-config path: $PKG_CONFIG_PATH"
echo ""

cd SourcePrint

# Clean to remove cached dynamic library references
echo "Cleaning build cache..."
xcodebuild -project SourcePrint.xcodeproj \
           -scheme SourcePrint \
           -configuration Release \
           clean \
           -derivedDataPath ./build \
           CODE_SIGN_IDENTITY="-" &>/dev/null

echo "Building..."
echo ""

# Build with static FFmpeg + required dependencies
xcodebuild -project SourcePrint.xcodeproj \
           -scheme SourcePrint \
           -configuration Release \
           build \
           -derivedDataPath ./build \
           CODE_SIGN_IDENTITY="-" \
           OTHER_LDFLAGS='-L'"$STATIC_BUILD_DIR"'/lib -lavfilter -lpostproc -lavdevice -lfreetype -lharfbuzz -lpng16 -llzma $(inherited)'

if [ $? -eq 0 ]; then
    echo "✅ SourcePrint build succeeded!"
    echo "App bundle: ./build/Build/Products/Release/SourcePrint.app"
    echo ""
    echo "📦 Using static FFmpeg libraries (no bundling needed)"
    echo "   App is now self-contained and doesn't require Homebrew/FFmpeg"
else
    echo "❌ SourcePrint build failed!"
    exit 1
fi

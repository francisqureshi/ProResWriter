#!/bin/bash

# SourcePrint macOS App Build Script with Static FFmpeg
# Forces static linking by overriding pkg-config

set -e

# Check for static FFmpeg build
STATIC_FFMPEG_DIR="$PWD/ffmpeg-build/install"

if [ ! -d "$STATIC_FFMPEG_DIR" ]; then
    echo "❌ Static FFmpeg not found at $STATIC_FFMPEG_DIR"
    echo "Run: ./build-static-ffmpeg.sh"
    exit 1
fi

# Make pkg-config wrapper executable
chmod +x "$PWD/pkg-config-static.sh"

# Override pkg-config with our static wrapper
export PATH="$PWD:$PATH"
ln -sf pkg-config-static.sh pkg-config 2>/dev/null || true

# Force pkg-config to ONLY use our static FFmpeg
export PKG_CONFIG_PATH="$STATIC_FFMPEG_DIR/lib/pkgconfig"
export PKG_CONFIG_LIBDIR="$STATIC_FFMPEG_DIR/lib/pkgconfig"

echo "🔨 Building SourcePrint with static FFmpeg..."
echo "   Static libraries: $STATIC_FFMPEG_DIR/lib"
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
           OTHER_LDFLAGS='-L'"$STATIC_FFMPEG_DIR"'/lib -lavfilter -lpostproc -lavdevice -L/opt/homebrew/opt/freetype/lib -lfreetype -L/opt/homebrew/opt/harfbuzz/lib -lharfbuzz -L/opt/homebrew/opt/libpng/lib -lpng16 $(inherited)'

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

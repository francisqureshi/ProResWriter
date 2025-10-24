#!/bin/bash

# SourcePrint Static FFmpeg Build
# Temporarily hides Homebrew FFmpeg to force static linking

set -e

# Check for static FFmpeg frameworks
FRAMEWORKS_DIR="$PWD/ffmpeg-frameworks"

if [ ! -d "$FRAMEWORKS_DIR" ]; then
    echo "❌ Static FFmpeg frameworks not found"
    echo "Run: ./build-static-ffmpeg.sh && ./build-static-frameworks.sh"
    exit 1
fi

echo "🔨 Building SourcePrint with static FFmpeg (hiding Homebrew during build)..."
echo ""

# Check if Homebrew FFmpeg exists
HOMEBREW_FFMPEG="/opt/homebrew/opt/ffmpeg@7"
HOMEBREW_FFMPEG_HIDDEN="/opt/homebrew/opt/ffmpeg@7.hidden"

if [ -d "$HOMEBREW_FFMPEG" ]; then
    echo "📦 Temporarily hiding Homebrew FFmpeg to force static linking..."
    sudo mv "$HOMEBREW_FFMPEG" "$HOMEBREW_FFMPEG_HIDDEN"
    HIDDEN_HOMEBREW=true
fi

# Trap to ensure we restore Homebrew FFmpeg even if build fails
function cleanup {
    if [ "$HIDDEN_HOMEBREW" = true ]; then
        echo ""
        echo "📦 Restoring Homebrew FFmpeg..."
        sudo mv "$HOMEBREW_FFMPEG_HIDDEN" "$HOMEBREW_FFMPEG"
    fi
}
trap cleanup EXIT

# Set pkg-config to only find our static FFmpeg
export PKG_CONFIG_PATH="$PWD/ffmpeg-build/install/lib/pkgconfig"

cd SourcePrint

echo "   Building SourcePrint..."
echo ""

# Build with static frameworks
xcodebuild -project SourcePrint.xcodeproj \
           -scheme SourcePrint \
           -configuration Release \
           build \
           -derivedDataPath ./build \
           CODE_SIGN_IDENTITY="-" \
           FRAMEWORK_SEARCH_PATHS="$FRAMEWORKS_DIR \$(inherited)"

if [ $? -eq 0 ]; then
    echo ""
    echo "✅ SourcePrint build succeeded!"
    echo "App bundle: ./build/Build/Products/Release/SourcePrint.app"
    echo ""
    echo "📦 App is now self-contained with static FFmpeg"
else
    echo "❌ Build failed!"
    exit 1
fi

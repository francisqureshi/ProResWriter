#!/bin/bash

# SourcePrint macOS App Build Script with SwiftFFmpeg Support
# Sets up environment variables for FFmpeg/SwiftFFmpeg and builds the SourcePrint app

export PKG_CONFIG_PATH="/opt/homebrew/lib/pkgconfig:$PKG_CONFIG_PATH"
export LIBRARY_PATH="/opt/homebrew/lib:$LIBRARY_PATH"  
export CPATH="/opt/homebrew/include:$CPATH"

echo "🔨 Building SourcePrint macOS app with ProResWriterCore support..."
cd SourcePrint
xcodebuild -project SourcePrint.xcodeproj \
           -scheme SourcePrint \
           -configuration Release \
           build \
           -derivedDataPath ./build \
           CODE_SIGN_IDENTITY="-" \
           CODE_SIGNING_REQUIRED=NO \
           CODE_SIGNING_ALLOWED=NO

if [ $? -eq 0 ]; then
    echo "✅ SourcePrint build succeeded!"
    echo "App bundle: ./build/Build/Products/Release/SourcePrint.app"
else
    echo "❌ SourcePrint build failed!"
    exit 1
fi

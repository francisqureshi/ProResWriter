#!/bin/bash

# ProResWriter GUI App Build Script with SwiftFFmpeg Support
# Sets up environment variables for FFmpeg/SwiftFFmpeg and builds the SourcePrinterApp target

export PKG_CONFIG_PATH="/opt/homebrew/lib/pkgconfig:$PKG_CONFIG_PATH"
export LIBRARY_PATH="/opt/homebrew/lib:$LIBRARY_PATH"  
export CPATH="/opt/homebrew/include:$CPATH"

echo "🔨 Building SourcePrinterApp (GUI) with SwiftFFmpeg support..."
xcodebuild -project ProResWriter.xcodeproj \
           -scheme SourcePrinterApp \
           -configuration Release \
           build \
           -derivedDataPath ./build \
           CODE_SIGN_IDENTITY="-" \
           CODE_SIGNING_REQUIRED=NO \
           CODE_SIGNING_ALLOWED=NO

if [ $? -eq 0 ]; then
    echo "✅ GUI App build succeeded!"
    echo "App Bundle: ./build/Build/Products/Release/SourcePrinterApp.app"
    echo ""
    echo "To run:"
    echo "open ./build/Build/Products/Release/SourcePrinterApp.app"
else
    echo "❌ GUI App build failed!"
    exit 1
fi
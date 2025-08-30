#!/bin/bash

# ProResWriter Build Script with SwiftFFmpeg Support
# Sets up environment variables for FFmpeg/SwiftFFmpeg and builds the project

export PKG_CONFIG_PATH="/opt/homebrew/lib/pkgconfig:$PKG_CONFIG_PATH"
export LIBRARY_PATH="/opt/homebrew/lib:$LIBRARY_PATH"  
export CPATH="/opt/homebrew/include:$CPATH"

echo "🔨 Building ProResWriter with SwiftFFmpeg support..."
xcodebuild -project ProResWriter.xcodeproj \
           -scheme ProResWriter \
           -configuration Release \
           build \
           -derivedDataPath ./build \
           CODE_SIGN_IDENTITY="-" \
           CODE_SIGNING_REQUIRED=NO \
           CODE_SIGNING_ALLOWED=NO

if [ $? -eq 0 ]; then
    echo "✅ Build succeeded!"
    echo "Executable: ./build/Build/Products/Release/ProResWriter"
else
    echo "❌ Build failed!"
    exit 1
fi
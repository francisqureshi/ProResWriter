#!/bin/bash

# ProResWriter GUI Preview Build (Debug mode for SwiftUI previews)
# Builds in Debug mode which enables SwiftUI previews

export PKG_CONFIG_PATH="/opt/homebrew/lib/pkgconfig:$PKG_CONFIG_PATH"
export LIBRARY_PATH="/opt/homebrew/lib:$LIBRARY_PATH"  
export CPATH="/opt/homebrew/include:$CPATH"

echo "🔨 Building SourcePrinterApp (Debug) for SwiftUI previews..."
xcodebuild -project ProResWriter.xcodeproj \
           -scheme SourcePrinterApp \
           -configuration Debug \
           build \
           -derivedDataPath ./build \
           CODE_SIGN_IDENTITY="-" \
           CODE_SIGNING_REQUIRED=NO \
           CODE_SIGNING_ALLOWED=NO

if [ $? -eq 0 ]; then
    echo "✅ Preview build succeeded!"
    echo "App Bundle: ./build/Build/Products/Debug/SourcePrinterApp.app"
    echo ""
    echo "SwiftUI previews should now work in Xcode!"
    echo "Try opening any UI/*.swift file and use Xcode Canvas"
else
    echo "❌ Preview build failed - need to fix compilation errors first"
    exit 1
fi
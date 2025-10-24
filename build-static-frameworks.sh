#!/bin/bash

# Convert static FFmpeg libraries to frameworks for SwiftFFmpeg
# Based on SwiftFFmpeg's build_framework.sh approach

set -e

STATIC_FFMPEG_DIR="$PWD/ffmpeg-build/install"
FRAMEWORKS_DIR="$PWD/ffmpeg-frameworks"
FFMPEG_VERSION="7.1.2"
FFMPEG_LIBS="libavcodec libavdevice libavfilter libavformat libavutil libpostproc libswresample libswscale"

echo "🔨 Converting static FFmpeg libraries to frameworks for SwiftFFmpeg"
echo ""

if [ ! -d "$STATIC_FFMPEG_DIR" ]; then
    echo "❌ Static FFmpeg not found at $STATIC_FFMPEG_DIR"
    echo "Run ./build-static-ffmpeg.sh first"
    exit 1
fi

# Create frameworks directory
rm -rf "$FRAMEWORKS_DIR"
mkdir -p "$FRAMEWORKS_DIR"

for LIB_NAME in $FFMPEG_LIBS; do
    echo "📦 Creating framework for $LIB_NAME..."

    LIB_FRAMEWORK="$FRAMEWORKS_DIR/$LIB_NAME.framework"

    # Create framework structure
    mkdir -p "$LIB_FRAMEWORK/Headers"

    # Copy headers
    if [ -d "$STATIC_FFMPEG_DIR/include/$LIB_NAME" ]; then
        cp -R "$STATIC_FFMPEG_DIR/include/$LIB_NAME/" "$LIB_FRAMEWORK/Headers/"
    fi

    # Copy static library as framework binary (no .a extension in framework)
    cp "$STATIC_FFMPEG_DIR/lib/$LIB_NAME.a" "$LIB_FRAMEWORK/$LIB_NAME"

    # Create Info.plist
    cat > "$LIB_FRAMEWORK/Info.plist" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleDevelopmentRegion</key>
	<string>en</string>
	<key>CFBundleExecutable</key>
	<string>$LIB_NAME</string>
	<key>CFBundleIdentifier</key>
	<string>org.ffmpeg.$LIB_NAME</string>
	<key>CFBundleInfoDictionaryVersion</key>
	<string>6.0</string>
	<key>CFBundleName</key>
	<string>$LIB_NAME</string>
	<key>CFBundlePackageType</key>
	<string>FMWK</string>
	<key>CFBundleShortVersionString</key>
	<string>$FFMPEG_VERSION</string>
	<key>CFBundleVersion</key>
	<string>$FFMPEG_VERSION</string>
	<key>CFBundleSignature</key>
	<string>????</string>
	<key>NSPrincipalClass</key>
	<string></string>
</dict>
</plist>
EOF

    echo "   ✅ $LIB_NAME.framework created"
done

echo ""
echo "✅ All static FFmpeg frameworks created at: $FRAMEWORKS_DIR"
echo ""
echo "📝 Next step: Update SourcePrint Xcode project to use these frameworks"
echo "   1. Open SourcePrint.xcodeproj in Xcode"
echo "   2. In Build Settings, add to FRAMEWORK_SEARCH_PATHS:"
echo "      $FRAMEWORKS_DIR"
echo "   3. Remove pkg-config dependency from build-sourceprint.sh"

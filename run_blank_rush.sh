#!/bin/bash

# ProResWriter Blank Rush Creator Script
# This script runs the blank rush creation process directly in the terminal
# to avoid Swift Process API issues with VideoToolbox

echo "🎬 ProResWriter Blank Rush Creator"
echo "=================================="

# Check if the executable exists
EXECUTABLE="./build/Build/Products/Release/ProResWriter"
if [ ! -f "$EXECUTABLE" ]; then
    echo "❌ ProResWriter executable not found at $EXECUTABLE"
    echo "Please build the project first with:"
    echo "xcodebuild -project ProResWriter.xcodeproj -scheme ProResWriter -configuration Release build -derivedDataPath ./build CODE_SIGN_IDENTITY=\"-\" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO"
    exit 1
fi

# Run import and linking first to get the parent-child relationships
echo "📁 Running import and linking process..."
$EXECUTABLE | grep -E "(🔗|📊|📁)" | head -20

echo ""
echo "🎬 Now running blank rush creation directly..."
echo "⏳ This will process each OCF file and create blank rushes..."
echo ""

# Extract the ffmpeg script commands and run them directly
SCRIPT_PATH="./build/Build/Products/Release/Resources/ffmpegScripts/timecode_black_frames_relative.sh"
OCF_FILE="/Users/fq/Movies/ProResWriter/9999 - COS AW ProResWriter/02_FOOTAGE/OCF/8MM/COS AW25_4K_4444_LR001_LOG/COS AW25_4K_4444_LR001_LOG.mov"
OUTPUT_FILE="/Users/fq/Movies/ProResWriter/9999 - COS AW ProResWriter/08_GRADE/02_GRADED CLIPS/03 INTERMEDIATE/blankRush/COS AW25_4K_4444_LR001_LOG_blankRush.mov"

if [ -f "$SCRIPT_PATH" ]; then
    echo "📝 Running ffmpeg script directly..."
    cd "$(dirname "$SCRIPT_PATH")"
    bash "$SCRIPT_PATH" "$OCF_FILE" "$OUTPUT_FILE"
    
    if [ $? -eq 0 ]; then
        echo ""
        echo "✅ Blank rush creation completed successfully!"
        echo "📄 Output file: $OUTPUT_FILE"
    else
        echo ""
        echo "❌ Blank rush creation failed"
    fi
else
    echo "❌ FFmpeg script not found at $SCRIPT_PATH"
fi
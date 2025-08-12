#!/bin/bash

# MXF Timecode Black Frames Script  
# Usage: ./timecode_black_frames.sh input.mxf [output.mxf]
# Creates black frames with running timecode burn-in
# If no output file specified, adds "_black_tc" to the input filename

# Check if input file is provided
if [ $# -eq 0 ]; then
    echo "Usage: $0 input.mxf [output.mxf]"
    echo "Example: $0 myfile.mxf"
    echo "Example: $0 myfile.mxf myfile_black_tc.mxf"
    exit 1
fi

INPUT="$1"

# Check if input file exists
if [ ! -f "$INPUT" ]; then
    echo "Error: Input file '$INPUT' not found!"
    exit 1
fi

# Set output filename
if [ $# -eq 2 ]; then
    OUTPUT="$2"
else
    # Generate output filename by adding "_black_tc" before the extension
    BASENAME="${INPUT%.*}"
    EXTENSION="${INPUT##*.}"
    OUTPUT="${BASENAME}_black_tc.${EXTENSION}"
fi

echo "Processing: $INPUT -> $OUTPUT"

# Extract timecode - check format metadata first, then stream metadata
TC_FULL=$(ffprobe -v error -show_entries format_tags=timecode -of default=noprint_wrappers=1:nokey=1 "$INPUT")
if [[ "$TC_FULL" = "" ]]; then
    # Try stream metadata if format metadata doesn't have timecode
    TC_FULL=$(ffprobe -v error -select_streams v:0 -show_entries stream_tags=timecode -of default=noprint_wrappers=1:nokey=1 "$INPUT")
fi
if [[ "$TC_FULL" = "" ]]; then
    echo "Warning: No timecode found in file, using 00:00:00:00"
    TC_FULL="00:00:00:00"
fi
echo "Source timecode: $TC_FULL"

# Parse the timecode into components (handle both : and ; separators for drop-frame)
# Replace semicolon with colon for consistent parsing
TC_NORMALIZED=$(echo "$TC_FULL" | sed 's/;/:/')
IFS=':' read -r TC_HH TC_MM TC_SS TC_FF <<< "$TC_NORMALIZED"
echo "Parsed - Hours: $TC_HH, Minutes: $TC_MM, Seconds: $TC_SS, Frames: $TC_FF"

# Get frame rate
FPS=$(ffprobe -v error -select_streams v -show_entries stream=r_frame_rate -of default=noprint_wrappers=1:nokey=1 "$INPUT")
if [[ "$FPS" = "" ]]; then
    echo "Warning: No frame rate found, defaulting to 24000/1001"
    FPS="24000/1001"
fi
echo "Frame rate: $FPS"

# Build the timecode string with proper escaping
TC_STRING="${TC_HH}\\:${TC_MM}\\:${TC_SS}\\:${TC_FF}"
echo "Timecode string: $TC_STRING"

# Get source video properties
WIDTH=$(ffprobe -v error -select_streams v -show_entries stream=width -of default=noprint_wrappers=1:nokey=1 "$INPUT")
HEIGHT=$(ffprobe -v error -select_streams v -show_entries stream=height -of default=noprint_wrappers=1:nokey=1 "$INPUT")
COMPANY=$(ffprobe -v error -show_entries format_tags=company_name -of default=noprint_wrappers=1:nokey=1 "$INPUT")
SAR=$(ffprobe -v error -select_streams v -show_entries stream=sample_aspect_ratio -of default=noprint_wrappers=1:nokey=1 "$INPUT")

echo "Source dimensions: ${WIDTH}x${HEIGHT}"
echo "Company: $COMPANY"
echo "Sample Aspect Ratio: $SAR"

# Determine final output dimensions
if [[ "$COMPANY" == "ARRI" && "$SAR" != "1:1" && "$SAR" != "" ]]; then
    echo "🎬 ARRI camera detected with non-square pixels (SAR: $SAR)"
    
    # Parse SAR to get numerator and denominator
    SAR_NUM=$(echo "$SAR" | cut -d':' -f1)
    SAR_DEN=$(echo "$SAR" | cut -d':' -f2)
    
    # Calculate corrected width using bc for precision
    FINAL_WIDTH=$(echo "scale=0; $WIDTH * $SAR_NUM / $SAR_DEN" | bc)
    FINAL_HEIGHT=$HEIGHT
    echo "📐 Applying SAR correction: ${WIDTH}x${HEIGHT} -> ${FINAL_WIDTH}x${FINAL_HEIGHT}"
else
    echo "📺 Using original dimensions: ${WIDTH}x${HEIGHT}"
    FINAL_WIDTH=$WIDTH
    FINAL_HEIGHT=$HEIGHT
fi

# Get source duration and clip name for black video generation
DURATION=$(ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$INPUT")
CLIP_NAME=$(basename "$INPUT" .mxf)
echo "⏱️  Source duration: ${DURATION}s"
echo "📎 Source clip name: $CLIP_NAME"

# Set up font path for Fira Code
FONT_PATH="Fonts/FiraCodeNerdFont-Regular.ttf"
if [[ ! -f "$FONT_PATH" ]]; then
    echo "⚠️  Fira Code font not found at $FONT_PATH, using system default"
    FONT_PATH=""
fi

# Build video filter with running timecode embedded in source string - TOP LEFT positioning
# We'll use the timecode parameter but add prefix/suffix text - 2.5% font size relative to height
if [[ -n "$FONT_PATH" ]]; then
    DRAWTEXT_FILTER="drawtext=fontfile=$FONT_PATH:text='SRC TC\\: ':fontsize=(h*0.025):fontcolor=white:box=1:boxcolor=black@0.8:boxborderw=5:x=(w*0.011):y=(h*0.03),drawtext=fontfile=$FONT_PATH:timecode='$TC_STRING':timecode_rate=$FPS:fontsize=(h*0.025):fontcolor=white:x=(w*0.13):y=(h*0.03),drawtext=fontfile=$FONT_PATH:text=' ---> $CLIP_NAME':fontsize=(h*0.025):fontcolor=white:x=(w*0.32):y=(h*0.03)"
else
    DRAWTEXT_FILTER="drawtext=text='SRC TC\\: ':fontsize=(h*0.025):fontcolor=white:box=1:boxcolor=black@0.8:boxborderw=5:x=(w*0.011):y=(h*0.03),drawtext=timecode='$TC_STRING':timecode_rate=$FPS:fontsize=(h*0.025):fontcolor=white:x=(w*0.13):y=(h*0.03),drawtext=text=' ---> $CLIP_NAME':fontsize=(h*0.025):fontcolor=white:x=(w*0.32):y=(h*0.03)"
fi

echo "📝 Format: SRC TC: [RUNNING] ---> $CLIP_NAME"

# Run ffmpeg to create black frames with timecode burn-in and copy metadata
echo "⚫ Creating black frames with running timecode, source info, and metadata..."
ffmpeg \
    -f lavfi -i "color=black:size=${FINAL_WIDTH}x${FINAL_HEIGHT}:duration=${DURATION}:rate=${FPS}" \
    -i "$INPUT" \
    -map 0:v -map_metadata 1 \
    -metadata timecode="$TC_FULL" \
    -vf "$DRAWTEXT_FILTER" \
    -c:v prores_ks -profile:v 4 \
    "$OUTPUT"

if [ $? -eq 0 ]; then
    echo "Success! Timecode burn-in completed: $OUTPUT"
else
    echo "Error: FFmpeg failed!"
    exit 1
fi

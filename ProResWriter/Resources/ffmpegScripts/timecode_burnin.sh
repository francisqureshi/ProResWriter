#!/bin/bash

# MXF Timecode Burn-in Script
# Usage: ./timecode_burnin.sh input.mxf [output.mxf]
# If no output file specified, adds "_timecode" to the input filename

# Check if input file is provided
if [ $# -eq 0 ]; then
    echo "Usage: $0 input.mxf [output.mxf]"
    echo "Example: $0 myfile.mxf"
    echo "Example: $0 myfile.mxf myfile_with_tc.mxf"
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
    # Generate output filename by adding "_timecode" before the extension
    BASENAME="${INPUT%.*}"
    EXTENSION="${INPUT##*.}"
    OUTPUT="${BASENAME}_timecode.${EXTENSION}"
fi

echo "Processing: $INPUT -> $OUTPUT"

# Extract timecode from the format metadata
TC_FULL=$(ffprobe -v error -show_entries format_tags=timecode -of default=noprint_wrappers=1:nokey=1 "$INPUT")
if [[ "$TC_FULL" = "" ]]; then
    echo "Warning: No timecode found in file, using 00:00:00:00"
    TC_FULL="00:00:00:00"
fi
echo "Source timecode: $TC_FULL"

# Parse the timecode into components
IFS=':' read -r TC_HH TC_MM TC_SS TC_FF <<< "$TC_FULL"
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

# Build video filter - start with timecode
VF_FILTER="drawtext=timecode='$TC_STRING':timecode_rate=$FPS:fontsize=120:fontcolor=white:box=1:boxcolor=black@0.8:boxborderw=10:x=50:y=50"

# Check for ARRI files and apply SAR correction automatically  
if [[ "$COMPANY" == "ARRI" && "$SAR" != "1:1" && "$SAR" != "" ]]; then
    echo "🎬 ARRI camera detected with non-square pixels (SAR: $SAR)"
    
    # Parse SAR to get numerator and denominator
    SAR_NUM=$(echo "$SAR" | cut -d':' -f1)
    SAR_DEN=$(echo "$SAR" | cut -d':' -f2)
    
    # Calculate corrected width using bc for precision
    CORRECTED_WIDTH=$(echo "scale=0; $WIDTH * $SAR_NUM / $SAR_DEN" | bc)
    echo "📐 Applying SAR correction: ${WIDTH}x${HEIGHT} -> ${CORRECTED_WIDTH}x${HEIGHT}"
    
    # Add scale filter before timecode to get proper display dimensions
    VF_FILTER="scale=${CORRECTED_WIDTH}:${HEIGHT},${VF_FILTER}"
else
    echo "📺 Using original dimensions: ${WIDTH}x${HEIGHT}"
fi

# Run ffmpeg with proper timecode burn-in
echo "🎞️  Starting conversion..."
ffmpeg -i "$INPUT" \
    -vf "$VF_FILTER" \
    -c:v prores_ks -profile:v 4 -c:a copy \
    "$OUTPUT"

if [ $? -eq 0 ]; then
    echo "Success! Timecode burn-in completed: $OUTPUT"
else
    echo "Error: FFmpeg failed!"
    exit 1
fi
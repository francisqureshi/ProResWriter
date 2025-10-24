#!/bin/bash

# Custom pkg-config wrapper that forces static FFmpeg libraries
# Overrides system pkg-config to prevent finding Homebrew FFmpeg

STATIC_FFMPEG_DIR="/Users/mac10/Projects/ProResWriter/ffmpeg-build/install"

# Only search in our static FFmpeg directory
export PKG_CONFIG_PATH="$STATIC_FFMPEG_DIR/lib/pkgconfig"
export PKG_CONFIG_LIBDIR="$STATIC_FFMPEG_DIR/lib/pkgconfig"

# Call real pkg-config with --static flag
/opt/homebrew/bin/pkg-config --static "$@"

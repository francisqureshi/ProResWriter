#!/bin/bash

# Custom pkg-config wrapper that forces static FFmpeg and dependencies
# Overrides system pkg-config to prevent finding Homebrew libraries

STATIC_FFMPEG_DIR="/Users/mac10/Projects/ProResWriter/ffmpeg-build/install"
STATIC_DEPS_DIR="/Users/mac10/Projects/ProResWriter/deps-build/install"

# Search in our static directories only (FFmpeg + dependencies)
export PKG_CONFIG_PATH="$STATIC_FFMPEG_DIR/lib/pkgconfig:$STATIC_DEPS_DIR/lib/pkgconfig"
export PKG_CONFIG_LIBDIR="$STATIC_FFMPEG_DIR/lib/pkgconfig:$STATIC_DEPS_DIR/lib/pkgconfig"

# Call real pkg-config with --static flag
/opt/homebrew/bin/pkg-config --static "$@"

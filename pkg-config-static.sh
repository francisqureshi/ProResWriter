#!/bin/bash

# Custom pkg-config wrapper that forces static FFmpeg and dependencies
# Overrides system pkg-config to prevent finding Homebrew libraries

STATIC_BUILD_DIR="/Users/mac10/Projects/SourcePrint/static-build/install"

# Search in our static build directory only (FFmpeg + dependencies)
export PKG_CONFIG_PATH="$STATIC_BUILD_DIR/lib/pkgconfig"
export PKG_CONFIG_LIBDIR="$STATIC_BUILD_DIR/lib/pkgconfig"

# Call real pkg-config with --static flag
/opt/homebrew/bin/pkg-config --static "$@"

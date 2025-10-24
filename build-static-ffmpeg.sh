#!/bin/bash

# Static FFmpeg 7.1.2 Build Script for SourcePrint
# Builds fully static FFmpeg libraries for macOS Apple Silicon (M4 Pro)
# Includes all features needed for ProResWriter: VideoToolbox, drawtext, color filters

set -e  # Exit on error

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${BLUE}🏗️  Static FFmpeg 7.1.2 Build for SourcePrint${NC}"
echo ""

# Configuration
FFMPEG_VERSION="7.1.2"
BUILD_DIR="$PWD/ffmpeg-build"
SOURCE_DIR="$BUILD_DIR/ffmpeg-${FFMPEG_VERSION}"
INSTALL_PREFIX="$BUILD_DIR/install"
DOWNLOAD_URL="https://ffmpeg.org/releases/ffmpeg-${FFMPEG_VERSION}.tar.xz"

# Create build directory
echo -e "${BLUE}📁 Setting up build directory...${NC}"
mkdir -p "$BUILD_DIR"
cd "$BUILD_DIR"

# Download FFmpeg source if not already present
if [ ! -f "ffmpeg-${FFMPEG_VERSION}.tar.xz" ]; then
    echo -e "${BLUE}⬇️  Downloading FFmpeg ${FFMPEG_VERSION}...${NC}"
    curl -L -o "ffmpeg-${FFMPEG_VERSION}.tar.xz" "$DOWNLOAD_URL"
else
    echo -e "${GREEN}✅ FFmpeg source already downloaded${NC}"
fi

# Extract source
if [ ! -d "$SOURCE_DIR" ]; then
    echo -e "${BLUE}📦 Extracting FFmpeg source...${NC}"
    tar xf "ffmpeg-${FFMPEG_VERSION}.tar.xz"
else
    echo -e "${GREEN}✅ FFmpeg source already extracted${NC}"
fi

cd "$SOURCE_DIR"

# Check for required system dependencies
echo ""
echo -e "${BLUE}🔍 Checking system dependencies...${NC}"

# Install minimal dependencies via Homebrew (freetype + harfbuzz for drawtext filter)
echo -e "${YELLOW}📦 Installing build dependencies via Homebrew...${NC}"
brew list freetype &>/dev/null || brew install freetype
brew list harfbuzz &>/dev/null || brew install harfbuzz
brew list pkg-config &>/dev/null || brew install pkg-config
brew list nasm &>/dev/null || brew install nasm  # For optimized assembly

echo -e "${GREEN}✅ Dependencies ready${NC}"

# Configure FFmpeg for static build
echo ""
echo -e "${BLUE}🔧 Configuring FFmpeg for static build...${NC}"
echo -e "${YELLOW}Target: Apple Silicon (arm64)${NC}"
echo -e "${YELLOW}Profile: Static libraries, VideoToolbox, minimal external deps${NC}"
echo ""

# Clean previous build if exists
make distclean 2>/dev/null || true

# Configure with static build settings
./configure \
    --prefix="$INSTALL_PREFIX" \
    --enable-static \
    --disable-shared \
    --enable-gpl \
    --enable-version3 \
    --enable-videotoolbox \
    --enable-libfreetype \
    --enable-libharfbuzz \
    --arch=arm64 \
    --cc="clang -arch arm64" \
    --cxx="clang++ -arch arm64" \
    --enable-optimizations \
    --enable-asm \
    --enable-neon \
    --disable-debug \
    --disable-doc \
    --disable-htmlpages \
    --disable-manpages \
    --disable-podpages \
    --disable-txtpages \
    --enable-pic \
    --extra-cflags="-I/opt/homebrew/include -O3 -fPIC" \
    --extra-ldflags="-L/opt/homebrew/lib" \
    --pkg-config-flags="--static" \
    --enable-filters \
    --enable-filter=color \
    --enable-filter=drawtext \
    --enable-filter=format \
    --enable-filter=scale

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✅ Configuration successful${NC}"
else
    echo -e "${RED}❌ Configuration failed${NC}"
    exit 1
fi

# Build FFmpeg
echo ""
echo -e "${BLUE}🔨 Building FFmpeg (this will take 10-15 minutes)...${NC}"
echo -e "${YELLOW}Using $(sysctl -n hw.ncpu) CPU cores${NC}"
echo ""

BUILD_START=$(date +%s)

make -j$(sysctl -n hw.ncpu)

if [ $? -eq 0 ]; then
    BUILD_END=$(date +%s)
    BUILD_TIME=$((BUILD_END - BUILD_START))
    echo ""
    echo -e "${GREEN}✅ Build successful in ${BUILD_TIME}s${NC}"
else
    echo -e "${RED}❌ Build failed${NC}"
    exit 1
fi

# Install to local prefix
echo ""
echo -e "${BLUE}📦 Installing to ${INSTALL_PREFIX}...${NC}"
make install

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✅ Installation successful${NC}"
else
    echo -e "${RED}❌ Installation failed${NC}"
    exit 1
fi

# Verify static libraries
echo ""
echo -e "${BLUE}🔍 Verifying static libraries...${NC}"

LIBS=(
    "libavformat.a"
    "libavcodec.a"
    "libavfilter.a"
    "libavutil.a"
    "libswscale.a"
    "libswresample.a"
    "libavdevice.a"
    "libpostproc.a"
)

ALL_FOUND=true
for lib in "${LIBS[@]}"; do
    if [ -f "$INSTALL_PREFIX/lib/$lib" ]; then
        SIZE=$(ls -lh "$INSTALL_PREFIX/lib/$lib" | awk '{print $5}')
        echo -e "${GREEN}  ✅ $lib ($SIZE)${NC}"
    else
        echo -e "${RED}  ❌ $lib NOT FOUND${NC}"
        ALL_FOUND=false
    fi
done

if [ "$ALL_FOUND" = true ]; then
    echo ""
    echo -e "${GREEN}✅ All static libraries built successfully!${NC}"
else
    echo ""
    echo -e "${RED}❌ Some libraries missing${NC}"
    exit 1
fi

# Test the build
echo ""
echo -e "${BLUE}🧪 Testing ffmpeg binary...${NC}"
"$INSTALL_PREFIX/bin/ffmpeg" -version | head -3

# Calculate total library size
TOTAL_SIZE=$(du -sh "$INSTALL_PREFIX/lib" | cut -f1)
echo ""
echo -e "${BLUE}📊 Build Summary:${NC}"
echo -e "  Installation: ${GREEN}$INSTALL_PREFIX${NC}"
echo -e "  Libraries: ${GREEN}$TOTAL_SIZE${NC}"
echo -e "  Headers: ${GREEN}$INSTALL_PREFIX/include${NC}"
echo -e "  Binary: ${GREEN}$INSTALL_PREFIX/bin/ffmpeg${NC}"

# Create usage instructions
cat > "$INSTALL_PREFIX/README.txt" << EOF
Static FFmpeg 7.1.2 Build for SourcePrint
==========================================

Installation Directory: $INSTALL_PREFIX

Libraries (static .a files):
  $INSTALL_PREFIX/lib/

Headers:
  $INSTALL_PREFIX/include/

FFmpeg Binary:
  $INSTALL_PREFIX/bin/ffmpeg

To use with SwiftFFmpeg:
========================

1. Update your Package.swift or Xcode build settings:

   LIBRARY_SEARCH_PATHS = $INSTALL_PREFIX/lib
   HEADER_SEARCH_PATHS = $INSTALL_PREFIX/include

2. Link against static libraries:
   -lavformat -lavcodec -lavfilter -lavutil -lswscale -lswresample

3. Add required frameworks:
   -framework VideoToolbox -framework CoreMedia -framework CoreVideo
   -framework CoreFoundation -lbz2 -lz -liconv

Features Included:
==================
✅ VideoToolbox ProRes encoding
✅ Drawtext filter (with freetype)
✅ Color filter
✅ Format filter
✅ Scale filter
✅ All standard codecs and formats
✅ Optimized for Apple Silicon (arm64)

Build Date: $(date)
FFmpeg Version: $FFMPEG_VERSION
EOF

echo ""
echo -e "${GREEN}✅✅✅ Static FFmpeg build complete! ✅✅✅${NC}"
echo ""
echo -e "${BLUE}📝 Next steps:${NC}"
echo -e "  1. Static libraries: ${GREEN}$INSTALL_PREFIX/lib${NC}"
echo -e "  2. Headers: ${GREEN}$INSTALL_PREFIX/include${NC}"
echo -e "  3. Update SwiftFFmpeg to use static libraries"
echo -e "  4. See ${GREEN}$INSTALL_PREFIX/README.txt${NC} for integration instructions"
echo ""
echo -e "${YELLOW}⏳ Total build time: $((BUILD_END - BUILD_START))s${NC}"

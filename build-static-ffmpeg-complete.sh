#!/bin/bash

# Complete Static FFmpeg 7.1.2 Build Script for SourcePrint
# Builds all dependencies and FFmpeg as fully static libraries for macOS Apple Silicon
# Includes: liblzma, libpng, freetype, harfbuzz, and FFmpeg with VideoToolbox, drawtext, color filters

set -e  # Exit on error

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${BLUE}🏗️  Complete Static FFmpeg Build for SourcePrint${NC}"
echo ""

# Configuration
PROJECT_ROOT="$PWD"
BUILD_DIR="$PROJECT_ROOT/static-build"
DEPS_BUILD_DIR="$BUILD_DIR/deps"
FFMPEG_BUILD_DIR="$BUILD_DIR/ffmpeg"
INSTALL_PREFIX="$BUILD_DIR/install"

# Library versions
LIBPNG_VERSION="1.6.44"
XZ_VERSION="5.6.3"
FREETYPE_VERSION="2.13.3"
HARFBUZZ_VERSION="10.1.0"
FFMPEG_VERSION="7.1.2"

# ============================================================================
# PHASE 1: BUILD STATIC DEPENDENCIES
# ============================================================================

echo -e "${BLUE}═══════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}  PHASE 1: Building Static Dependencies${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════${NC}"
echo ""

mkdir -p "$DEPS_BUILD_DIR"
cd "$DEPS_BUILD_DIR"

# Install build tools first
echo -e "${YELLOW}📦 Installing build tools...${NC}"
brew list pkg-config &>/dev/null || brew install pkg-config
brew list nasm &>/dev/null || brew install nasm

# Create install directories
mkdir -p "$INSTALL_PREFIX/lib/pkgconfig"
mkdir -p "$INSTALL_PREFIX/include"
mkdir -p "$INSTALL_PREFIX/bin"

# Set PKG_CONFIG_PATH early so all builds can find dependencies
export PKG_CONFIG_PATH="$INSTALL_PREFIX/lib/pkgconfig:$PKG_CONFIG_PATH"
echo -e "${GREEN}✅ Build tools ready${NC}"
echo -e "${BLUE}📝 PKG_CONFIG_PATH: $PKG_CONFIG_PATH${NC}"
echo ""

echo -e "${BLUE}📥 Downloading dependency source tarballs...${NC}"

# Download libpng
if [ ! -f "libpng-${LIBPNG_VERSION}.tar.xz" ]; then
    echo "  Downloading libpng ${LIBPNG_VERSION}..."
    curl -L -o "libpng-${LIBPNG_VERSION}.tar.xz" "https://downloads.sourceforge.net/project/libpng/libpng16/${LIBPNG_VERSION}/libpng-${LIBPNG_VERSION}.tar.xz"
fi

# Download xz (liblzma)
if [ ! -f "xz-${XZ_VERSION}.tar.xz" ]; then
    echo "  Downloading xz ${XZ_VERSION}..."
    curl -L -o "xz-${XZ_VERSION}.tar.xz" "https://github.com/tukaani-project/xz/releases/download/v${XZ_VERSION}/xz-${XZ_VERSION}.tar.xz"
fi

# Download freetype
if [ ! -f "freetype-${FREETYPE_VERSION}.tar.xz" ]; then
    echo "  Downloading freetype ${FREETYPE_VERSION}..."
    curl -L -o "freetype-${FREETYPE_VERSION}.tar.xz" "https://download.savannah.gnu.org/releases/freetype/freetype-${FREETYPE_VERSION}.tar.xz"
fi

# Download harfbuzz
if [ ! -f "harfbuzz-${HARFBUZZ_VERSION}.tar.xz" ]; then
    echo "  Downloading harfbuzz ${HARFBUZZ_VERSION}..."
    curl -L -o "harfbuzz-${HARFBUZZ_VERSION}.tar.xz" "https://github.com/harfbuzz/harfbuzz/releases/download/${HARFBUZZ_VERSION}/harfbuzz-${HARFBUZZ_VERSION}.tar.xz"
fi

echo -e "${GREEN}✅ All dependency sources downloaded${NC}"
echo ""

# Build liblzma first (no dependencies)
echo -e "${BLUE}🔨 Building liblzma ${XZ_VERSION}...${NC}"
tar -xf "xz-${XZ_VERSION}.tar.xz"
cd "xz-${XZ_VERSION}"
./configure --prefix="$INSTALL_PREFIX" --enable-static --disable-shared --disable-doc
make -j$(sysctl -n hw.ncpu)
make install
cd ..
echo -e "${GREEN}✅ liblzma installed${NC}"
echo ""

# Build libpng (depends on zlib, which is in macOS SDK)
echo -e "${BLUE}🔨 Building libpng ${LIBPNG_VERSION}...${NC}"
tar -xf "libpng-${LIBPNG_VERSION}.tar.xz"
cd "libpng-${LIBPNG_VERSION}"
./configure --prefix="$INSTALL_PREFIX" --enable-static --disable-shared
make -j$(sysctl -n hw.ncpu)
make install
cd ..

# Verify libpng pkg-config file was created
if [ -f "$INSTALL_PREFIX/lib/pkgconfig/libpng16.pc" ]; then
    echo -e "${GREEN}✅ libpng installed with pkg-config support${NC}"
else
    echo -e "${RED}❌ Warning: libpng16.pc not found${NC}"
fi
echo ""

# Build freetype (depends on libpng)
echo -e "${BLUE}🔨 Building freetype ${FREETYPE_VERSION}...${NC}"
tar -xf "freetype-${FREETYPE_VERSION}.tar.xz"
cd "freetype-${FREETYPE_VERSION}"
./configure --prefix="$INSTALL_PREFIX" --enable-static --disable-shared \
    --with-png=yes \
    --with-brotli=no
make -j$(sysctl -n hw.ncpu)
make install
cd ..
echo -e "${GREEN}✅ freetype installed${NC}"
echo ""

# Build harfbuzz (depends on freetype)
echo -e "${BLUE}🔨 Building harfbuzz ${HARFBUZZ_VERSION}...${NC}"
tar -xf "harfbuzz-${HARFBUZZ_VERSION}.tar.xz"
cd "harfbuzz-${HARFBUZZ_VERSION}"

# HarfBuzz uses meson build system
if ! command -v meson &> /dev/null; then
    echo -e "${YELLOW}Installing meson build system...${NC}"
    brew install meson
fi

meson setup build \
    --prefix="$INSTALL_PREFIX" \
    --default-library=static \
    -Dfreetype=enabled \
    -Dglib=disabled \
    -Dgobject=disabled \
    -Dcairo=disabled \
    -Dicu=disabled \
    -Dgraphite=disabled \
    -Dtests=disabled \
    -Ddocs=disabled \
    --pkg-config-path="$INSTALL_PREFIX/lib/pkgconfig"

meson compile -C build
meson install -C build
cd ..
echo -e "${GREEN}✅ harfbuzz installed${NC}"
echo ""

# Verify dependency static libraries
echo -e "${BLUE}🔍 Verifying dependency static libraries...${NC}"
DEPS_LIBS=(
    "liblzma.a"
    "libpng16.a"
    "libfreetype.a"
    "libharfbuzz.a"
)

ALL_DEPS_FOUND=true
for lib in "${DEPS_LIBS[@]}"; do
    if [ -f "$INSTALL_PREFIX/lib/$lib" ]; then
        SIZE=$(ls -lh "$INSTALL_PREFIX/lib/$lib" | awk '{print $5}')
        echo -e "${GREEN}  ✅ $lib ($SIZE)${NC}"
    else
        echo -e "${RED}  ❌ $lib NOT FOUND${NC}"
        ALL_DEPS_FOUND=false
    fi
done

if [ "$ALL_DEPS_FOUND" = false ]; then
    echo ""
    echo -e "${RED}❌ Some dependency libraries missing${NC}"
    exit 1
fi

echo ""
echo -e "${GREEN}✅✅✅ Phase 1 Complete: All dependencies built successfully! ✅✅✅${NC}"
echo ""

# ============================================================================
# PHASE 2: BUILD STATIC FFMPEG
# ============================================================================

echo -e "${BLUE}═══════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}  PHASE 2: Building Static FFmpeg${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════${NC}"
echo ""

mkdir -p "$FFMPEG_BUILD_DIR"
cd "$FFMPEG_BUILD_DIR"

# Download FFmpeg source if not already present
DOWNLOAD_URL="https://ffmpeg.org/releases/ffmpeg-${FFMPEG_VERSION}.tar.xz"
if [ ! -f "ffmpeg-${FFMPEG_VERSION}.tar.xz" ]; then
    echo -e "${BLUE}⬇️  Downloading FFmpeg ${FFMPEG_VERSION}...${NC}"
    curl -L -o "ffmpeg-${FFMPEG_VERSION}.tar.xz" "$DOWNLOAD_URL"
else
    echo -e "${GREEN}✅ FFmpeg source already downloaded${NC}"
fi

# Extract source
SOURCE_DIR="$FFMPEG_BUILD_DIR/ffmpeg-${FFMPEG_VERSION}"
if [ ! -d "$SOURCE_DIR" ]; then
    echo -e "${BLUE}📦 Extracting FFmpeg source...${NC}"
    tar xf "ffmpeg-${FFMPEG_VERSION}.tar.xz"
else
    echo -e "${GREEN}✅ FFmpeg source already extracted${NC}"
fi

cd "$SOURCE_DIR"

# Configure FFmpeg for static build
echo ""
echo -e "${BLUE}🔧 Configuring FFmpeg for static build...${NC}"
echo -e "${YELLOW}Target: Apple Silicon (arm64)${NC}"
echo -e "${YELLOW}Profile: Static libraries, VideoToolbox, minimal external deps${NC}"
echo ""

# Clean previous build if exists
make distclean 2>/dev/null || true

# PKG_CONFIG_PATH already set in Phase 1 to find our static dependencies

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
    --disable-xlib \
    --disable-libxcb \
    --disable-libxcb-shm \
    --disable-libxcb-xfixes \
    --disable-libxcb-shape \
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
    --extra-cflags="-I$INSTALL_PREFIX/include -O3 -fPIC" \
    --extra-ldflags="-L$INSTALL_PREFIX/lib" \
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

# Verify FFmpeg static libraries
echo ""
echo -e "${BLUE}🔍 Verifying FFmpeg static libraries...${NC}"

FFMPEG_LIBS=(
    "libavformat.a"
    "libavcodec.a"
    "libavfilter.a"
    "libavutil.a"
    "libswscale.a"
    "libswresample.a"
    "libavdevice.a"
    "libpostproc.a"
)

ALL_FFMPEG_FOUND=true
for lib in "${FFMPEG_LIBS[@]}"; do
    if [ -f "$INSTALL_PREFIX/lib/$lib" ]; then
        SIZE=$(ls -lh "$INSTALL_PREFIX/lib/$lib" | awk '{print $5}')
        echo -e "${GREEN}  ✅ $lib ($SIZE)${NC}"
    else
        echo -e "${RED}  ❌ $lib NOT FOUND${NC}"
        ALL_FFMPEG_FOUND=false
    fi
done

if [ "$ALL_FFMPEG_FOUND" = false ]; then
    echo ""
    echo -e "${RED}❌ Some FFmpeg libraries missing${NC}"
    exit 1
fi

echo ""
echo -e "${GREEN}✅ All FFmpeg static libraries built successfully!${NC}"

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
Static FFmpeg 7.1.2 Complete Build for SourcePrint
===================================================

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

To use with ZigFFmpeg:
======================

1. Copy the libraries and headers to your FFmpeg directory:

   cp -r $INSTALL_PREFIX/lib/* /path/to/your/FFmpeg/lib/
   cp -r $INSTALL_PREFIX/include/* /path/to/your/FFmpeg/include/

2. Or update your build.zig to point to this installation:

   LIBRARY_SEARCH_PATHS: $INSTALL_PREFIX/lib
   INCLUDE_SEARCH_PATHS: $INSTALL_PREFIX/include

Features Included:
==================
✅ VideoToolbox ProRes encoding
✅ Drawtext filter (with freetype + harfbuzz)
✅ Color filter
✅ Format filter
✅ Scale filter
✅ All standard codecs and formats
✅ Optimized for Apple Silicon (arm64)

Dependencies Built:
===================
• liblzma ${XZ_VERSION}
• libpng ${LIBPNG_VERSION}
• freetype ${FREETYPE_VERSION}
• harfbuzz ${HARFBUZZ_VERSION}

Build Date: $(date)
FFmpeg Version: $FFMPEG_VERSION
EOF

echo ""
echo -e "${GREEN}✅✅✅ COMPLETE: Static FFmpeg Build Finished Successfully! ✅✅✅${NC}"
echo ""
echo -e "${BLUE}📝 Next steps:${NC}"
echo -e "  1. Static libraries: ${GREEN}$INSTALL_PREFIX/lib${NC}"
echo -e "  2. Headers: ${GREEN}$INSTALL_PREFIX/include${NC}"
echo -e "  3. Update SwiftFFmpeg to use static libraries"
echo -e "  4. See ${GREEN}$INSTALL_PREFIX/README.txt${NC} for integration instructions"
echo ""
echo -e "${YELLOW}⏳ Total FFmpeg build time: ${BUILD_TIME}s${NC}"
echo ""

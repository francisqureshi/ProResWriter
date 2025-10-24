#!/bin/bash

# Build static versions of remaining FFmpeg dependencies
# Eliminates all Homebrew dependencies for truly self-contained SourcePrint

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${BLUE}📦 Building static dependencies for FFmpeg${NC}"
echo ""

BUILD_DIR="$PWD/static-build/deps"
INSTALL_PREFIX="$PWD/static-build/install"

mkdir -p "$BUILD_DIR"
cd "$BUILD_DIR"

# Library versions
LIBPNG_VERSION="1.6.44"
XZ_VERSION="5.6.3"
FREETYPE_VERSION="2.13.3"
HARFBUZZ_VERSION="10.1.0"

echo -e "${BLUE}📥 Downloading source tarballs...${NC}"

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

echo -e "${GREEN}✅ All sources downloaded${NC}"
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
echo -e "${GREEN}✅ libpng installed${NC}"
echo ""

# Build freetype (depends on libpng)
echo -e "${BLUE}🔨 Building freetype ${FREETYPE_VERSION}...${NC}"
tar -xf "freetype-${FREETYPE_VERSION}.tar.xz"
cd "freetype-${FREETYPE_VERSION}"
./configure --prefix="$INSTALL_PREFIX" --enable-static --disable-shared \
    --with-png=yes \
    --with-brotli=no \
    PKG_CONFIG_PATH="$INSTALL_PREFIX/lib/pkgconfig"
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

# Verify all static libraries
echo -e "${BLUE}🔍 Verifying static libraries...${NC}"
LIBS=(
    "liblzma.a"
    "libpng16.a"
    "libfreetype.a"
    "libharfbuzz.a"
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
    echo -e "${GREEN}✅✅✅ All static dependencies built successfully! ✅✅✅${NC}"
    echo ""
    echo -e "${BLUE}📝 Installation:${NC} $INSTALL_PREFIX"
    echo -e "${BLUE}📝 Libraries:${NC} $INSTALL_PREFIX/lib"
    echo -e "${BLUE}📝 Headers:${NC} $INSTALL_PREFIX/include"
    echo ""
    echo -e "${YELLOW}Next step: Rebuild FFmpeg to use these static dependencies${NC}"
else
    echo ""
    echo -e "${RED}❌ Some libraries missing${NC}"
    exit 1
fi

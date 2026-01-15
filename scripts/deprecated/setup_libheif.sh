#!/bin/bash
# Build script for libheif (static library, no brew dependency)
# Similar to setup_openh264.sh and setup_ffmpeg.sh

set -e

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
THIRD_PARTY_DIR="$PROJECT_ROOT/third_party"
SOURCE_DIR="$THIRD_PARTY_DIR/sources"
INSTALL_DIR="$THIRD_PARTY_DIR/libheif_install"

# Get number of CPU cores
CORES=$(sysctl -n hw.ncpu 2>/dev/null || nproc 2>/dev/null || echo 4)

echo "=========================================="
echo "Building libheif (static library)"
echo "=========================================="
echo "Project root: $PROJECT_ROOT"
echo "Install directory: $INSTALL_DIR"
echo ""

# Create directories
mkdir -p "$SOURCE_DIR"
mkdir -p "$INSTALL_DIR"

cd "$SOURCE_DIR"

# Download libheif source if not present
LIBHEIF_VERSION="1.18.0"
if [ ! -d "libheif-$LIBHEIF_VERSION" ]; then
    echo "Downloading libheif $LIBHEIF_VERSION..."
    curl -L "https://github.com/strukturag/libheif/releases/download/v$LIBHEIF_VERSION/libheif-$LIBHEIF_VERSION.tar.gz" | tar xz
fi

cd "libheif-$LIBHEIF_VERSION"

# Clean previous build
rm -rf build
mkdir -p build
cd build

# Configure for static build
# Note: We disable optional codecs to reduce dependencies
# For HEIC decoding, we mainly need libde265 support
echo "Configuring libheif..."
cmake .. \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX="$INSTALL_DIR" \
    -DCMAKE_POSITION_INDEPENDENT_CODE=ON \
    -DBUILD_SHARED_LIBS=OFF \
    -DENABLE_PLUGIN_LOADING=OFF \
    -DWITH_AOM=OFF \
    -DWITH_DAV1D=OFF \
    -DWITH_RAV1E=OFF \
    -DWITH_X265=OFF \
    -DWITH_LIBDE265=ON \
    -DWITH_EXAMPLES=OFF \
    -DWITH_TESTS=OFF \
    -DCMAKE_C_FLAGS="-fPIC" \
    -DCMAKE_CXX_FLAGS="-fPIC"

echo "Building libheif..."
make -j"$CORES"

echo "Installing libheif..."
make install

echo ""
echo "=========================================="
echo "libheif build complete!"
echo "Location: $INSTALL_DIR"
echo ""
echo "Static library: $INSTALL_DIR/lib/libheif.a"
echo "Headers: $INSTALL_DIR/include/libheif"
echo "=========================================="


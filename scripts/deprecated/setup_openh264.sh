#!/bin/bash
set -e

# Build OpenH264 library (BSD-licensed, LGPL-compatible)
# This provides H.264 encoding support for platforms without VideoToolbox

PROJECT_ROOT="$(pwd)"
THIRD_PARTY_DIR="$PROJECT_ROOT/third_party"
INSTALL_DIR="$THIRD_PARTY_DIR/openh264_install"
SOURCE_DIR="$THIRD_PARTY_DIR/sources"

mkdir -p "$INSTALL_DIR"
mkdir -p "$SOURCE_DIR"

# Number of cores for build
CORES=$(sysctl -n hw.ncpu 2>/dev/null || nproc 2>/dev/null || echo 4)

# Download and build OpenH264
cd "$SOURCE_DIR"
if [ ! -d "openh264" ]; then
    echo "Cloning OpenH264 repository..."
    git clone https://github.com/cisco/openh264.git
fi

cd openh264

# Determine architecture
ARCH="${1:-$(uname -m)}"
BUILD_DIR="$THIRD_PARTY_DIR/openh264_build_$ARCH"
mkdir -p "$BUILD_DIR"

echo "Building OpenH264 for $ARCH..."

# Clean previous build
make clean 2>/dev/null || true

# Build OpenH264
# Note: OpenH264 doesn't have a configure script, it uses Makefile directly
# We need to set PREFIX for installation
make -j"$CORES" PREFIX="$BUILD_DIR"
make install PREFIX="$BUILD_DIR"

echo "OpenH264 installed at $BUILD_DIR"

# Create pkg-config file so FFmpeg's configure can locate OpenH264 via pkg-config
mkdir -p "$BUILD_DIR/lib/pkgconfig"

cat > "$BUILD_DIR/lib/pkgconfig/openh264.pc" <<EOF
prefix=$BUILD_DIR
exec_prefix=\${prefix}
libdir=\${exec_prefix}/lib
includedir=\${prefix}/include

Name: openh264
Description: OpenH264 is a codec library which supports H.264 encoding and decoding
Version: 2.4.1
Libs: -L\${libdir} -lopenh264
Cflags: -I\${includedir}
EOF

echo ""
echo "pkg-config file generated at: $BUILD_DIR/lib/pkgconfig/openh264.pc"
echo ""
echo "To use with FFmpeg, add to FFmpeg configure:"
echo "  --enable-libopenh264"
echo "  --extra-cflags=-I$BUILD_DIR/include"
echo "  --extra-ldflags=-L$BUILD_DIR/lib"


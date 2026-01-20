#!/bin/bash
set -euo pipefail

# Build OpenH264 for Windows host (static).
# Installs into: third_party/openh264_install/windows/x86_64
# Requires: MSYS2 with MinGW-w64 toolchain, make, nasm

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
THIRD_PARTY_DIR="$PROJECT_ROOT/third_party"
SOURCE_DIR="$THIRD_PARTY_DIR/sources"

mkdir -p "$SOURCE_DIR"

# Windows builds are typically x86_64
ABI_DIR="x86_64"
OPENH264_ARCH="x86_64"

INSTALL_DIR="$THIRD_PARTY_DIR/openh264_install/windows/$ABI_DIR"
BUILD_DIR="$THIRD_PARTY_DIR/openh264_build_windows_$ABI_DIR"

CORES="$(nproc 2>/dev/null || echo 4)"

cd "$SOURCE_DIR"
if [ ! -d "openh264" ]; then
  echo "Cloning OpenH264..."
  git clone https://github.com/cisco/openh264.git
fi

cd openh264
git checkout master 2>/dev/null || true

echo "Building OpenH264 for windows/$ABI_DIR..."
make clean 2>/dev/null || true

mkdir -p "$BUILD_DIR" "$INSTALL_DIR"

# Build static only for Windows
# OpenH264 uses OS=mingw_nt for MinGW-w64 builds on Windows
make -j"$CORES" OS=mingw_nt ARCH="$OPENH264_ARCH" libopenh264.a

mkdir -p "$INSTALL_DIR/lib" "$INSTALL_DIR/include/wels" "$INSTALL_DIR/lib/pkgconfig"
cp -f libopenh264.a "$INSTALL_DIR/lib/"
cp -f codec/api/wels/*.h "$INSTALL_DIR/include/wels/" 2>/dev/null || true

cat > "$INSTALL_DIR/lib/pkgconfig/openh264.pc" <<EOF
prefix=$INSTALL_DIR
exec_prefix=\${prefix}
libdir=\${exec_prefix}/lib
includedir=\${prefix}/include

Name: openh264
Description: OpenH264 is a codec library which supports H.264 encoding and decoding
Version: 2.6.0
Libs: -L\${libdir} -lopenh264
Cflags: -I\${includedir}
EOF

echo "OpenH264 installed: $INSTALL_DIR"

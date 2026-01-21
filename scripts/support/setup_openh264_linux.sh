#!/bin/bash
set -euo pipefail

# Build OpenH264 for Linux host (static).
# Installs into: third_party/openh264_install/linux/<arch>

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
THIRD_PARTY_DIR="$PROJECT_ROOT/third_party"
GENERATED_DIR="$THIRD_PARTY_DIR/generated"
SOURCE_DIR="$GENERATED_DIR/sources"

mkdir -p "$SOURCE_DIR"

host_arch="$(uname -m)"
case "$host_arch" in
  x86_64) OPENH264_ARCH="x86_64" ; ABI_DIR="x86_64" ;;
  aarch64|arm64) OPENH264_ARCH="arm64" ; ABI_DIR="arm64" ;;
  *) echo "Unsupported linux arch: $host_arch"; exit 2 ;;
esac

INSTALL_DIR="$GENERATED_DIR/openh264_install/linux/$ABI_DIR"
BUILD_DIR="$GENERATED_DIR/openh264_build_linux_$ABI_DIR"

CORES="$(nproc 2>/dev/null || echo 4)"

cd "$SOURCE_DIR"
if [ ! -d "openh264" ]; then
  echo "Cloning OpenH264..."
  git clone https://github.com/cisco/openh264.git
fi

cd openh264
git checkout master 2>/dev/null || true

echo "Building OpenH264 for linux/$ABI_DIR..."
make clean 2>/dev/null || true

mkdir -p "$BUILD_DIR" "$INSTALL_DIR"

# Build static only
make -j"$CORES" OS=linux ARCH="$OPENH264_ARCH" libopenh264.a

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
Libs: -L\${libdir} -lopenh264 -lstdc++
Cflags: -I\${includedir}
EOF

echo "OpenH264 installed: $INSTALL_DIR"



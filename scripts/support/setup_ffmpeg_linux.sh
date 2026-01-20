#!/bin/bash
set -euo pipefail

# Build FFmpeg for Linux host (static, LGPL).
# Installs into: third_party/ffmpeg_install/linux/<arch>
# Requires: pkg-config, make, a C compiler, yasm/nasm (optional but recommended), and OpenH264 (via setup_openh264_linux.sh)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
THIRD_PARTY_DIR="$PROJECT_ROOT/third_party"
SOURCE_DIR="$THIRD_PARTY_DIR/sources"

mkdir -p "$SOURCE_DIR"

host_arch="$(uname -m)"
case "$host_arch" in
  x86_64) FFMPEG_ARCH="x86_64" ABI_DIR="x86_64" ;;
  aarch64|arm64) FFMPEG_ARCH="aarch64" ABI_DIR="arm64" ;;
  *) echo "Unsupported linux arch: $host_arch"; exit 2 ;;
esac

INSTALL_DIR="$THIRD_PARTY_DIR/ffmpeg_install/linux/$ABI_DIR"
BUILD_DIR="$THIRD_PARTY_DIR/ffmpeg_build_linux_$ABI_DIR"

OPENH264_DIR="$THIRD_PARTY_DIR/openh264_install/linux/$ABI_DIR"
if [ ! -f "$OPENH264_DIR/lib/libopenh264.a" ]; then
  echo "ERROR: OpenH264 not found at $OPENH264_DIR. Run: ./setup_all.sh --linux"
  exit 2
fi

CORES="$(nproc 2>/dev/null || echo 4)"

cd "$SOURCE_DIR"
if [ ! -d "ffmpeg-8.0.1" ]; then
  echo "Downloading FFmpeg 8.0.1..."
  curl -L https://ffmpeg.org/releases/ffmpeg-8.0.1.tar.bz2 | tar xj
fi

cd "$SOURCE_DIR/ffmpeg-8.0.1"
make distclean 2>/dev/null || true

export PKG_CONFIG_ALLOW_CROSS=1
export PKG_CONFIG_PATH="$OPENH264_DIR/lib/pkgconfig"
export PKG_CONFIG_LIBDIR="$OPENH264_DIR/lib/pkgconfig"

mkdir -p "$BUILD_DIR"

echo "Configuring FFmpeg for linux/$ABI_DIR..."
./configure \
  --prefix="$BUILD_DIR" \
  --pkg-config-flags="--static" \
  --pkg-config=pkg-config \
  --enable-static \
  --disable-shared \
  --disable-programs \
  --disable-doc \
  --enable-avcodec \
  --enable-avformat \
  --enable-avutil \
  --enable-swscale \
  --enable-swresample \
  --enable-zlib \
  --disable-avdevice \
  --disable-avfilter \
  --disable-debug \
  --disable-ffplay \
  --disable-ffprobe \
  --disable-gpl \
  --disable-nonfree \
  --arch="$FFMPEG_ARCH" \
  --enable-libopenh264 \
  --enable-encoder=libopenh264 \
  --enable-decoder=libopenh264 \
  --extra-cflags="-I$OPENH264_DIR/include" \
  --extra-ldflags="-L$OPENH264_DIR/lib" \
  --extra-libs="-lm -lpthread"

make -j"$CORES"
make install

# Copy into install dir with normalized pkg-config
mkdir -p "$INSTALL_DIR/lib" "$INSTALL_DIR/include" "$INSTALL_DIR/lib/pkgconfig"
cp -r "$BUILD_DIR/include/"* "$INSTALL_DIR/include/"
cp "$BUILD_DIR/lib/"*.a "$INSTALL_DIR/lib/"
cp "$BUILD_DIR/lib/pkgconfig/"*.pc "$INSTALL_DIR/lib/pkgconfig/"

for PC_FILE in "$INSTALL_DIR/lib/pkgconfig/"*.pc; do
  sed -i "s|^prefix=.*|prefix=${INSTALL_DIR}|g" "$PC_FILE" || true
  sed -i "s|^exec_prefix=.*|exec_prefix=\\\${prefix}|g" "$PC_FILE" || true
  sed -i "s|^libdir=.*|libdir=\\\${prefix}/lib|g" "$PC_FILE" || true
  sed -i "s|^includedir=.*|includedir=\\\${prefix}/include|g" "$PC_FILE" || true
done

echo "FFmpeg installed: $INSTALL_DIR"



#!/bin/bash
set -euo pipefail

# Build FFmpeg for Windows host (static, LGPL).
# Installs into: third_party/ffmpeg_install/windows/x86_64
# Requires: MSYS2 with MinGW-w64 toolchain, pkg-config, make, nasm, and OpenH264 (via setup_openh264_windows.sh)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
THIRD_PARTY_DIR="$PROJECT_ROOT/third_party"
SOURCE_DIR="$THIRD_PARTY_DIR/sources"

mkdir -p "$SOURCE_DIR"

# Windows builds are typically x86_64
ABI_DIR="x86_64"
FFMPEG_ARCH="x86_64"

INSTALL_DIR="$THIRD_PARTY_DIR/ffmpeg_install/windows/$ABI_DIR"
BUILD_DIR="$THIRD_PARTY_DIR/ffmpeg_build_windows_$ABI_DIR"

OPENH264_DIR="$THIRD_PARTY_DIR/openh264_install/windows/$ABI_DIR"
if [ ! -f "$OPENH264_DIR/lib/libopenh264.a" ]; then
  echo "ERROR: OpenH264 not found at $OPENH264_DIR. Run: ./setup_all.bat --windows"
  exit 2
fi

CORES="$(nproc 2>/dev/null || echo 4)"

# Ensure MinGW-w64 bin directory is in PATH (needed for cross-compiler tools like nm, ar, etc.)
export PATH="/mingw64/bin:/usr/bin:$PATH"

# Check for MinGW-w64 compiler
if command -v x86_64-w64-mingw32-gcc >/dev/null 2>&1; then
  CC="x86_64-w64-mingw32-gcc"
  CROSS_PREFIX="x86_64-w64-mingw32-"
  # Verify cross-tools are available
  if ! command -v "${CROSS_PREFIX}nm" >/dev/null 2>&1; then
    echo "WARNING: ${CROSS_PREFIX}nm not found. Trying without cross-prefix..."
    CROSS_PREFIX=""
  fi
elif command -v gcc >/dev/null 2>&1; then
  # Check if gcc is MinGW-w64
  if gcc -dumpmachine 2>/dev/null | grep -q "mingw"; then
    CC="gcc"
    CROSS_PREFIX=""
  else
    echo "ERROR: MinGW-w64 compiler not found. Install with: pacman -S mingw-w64-x86_64-gcc"
    exit 2
  fi
else
  echo "ERROR: No C compiler found. Install MinGW-w64 with: pacman -S mingw-w64-x86_64-gcc"
  exit 2
fi

cd "$SOURCE_DIR"
if [ ! -d "ffmpeg-8.0.1" ]; then
  echo "Downloading FFmpeg 8.0.1..."
  curl -L https://ffmpeg.org/releases/ffmpeg-8.0.1.tar.bz2 | tar xj
fi

cd "$SOURCE_DIR/ffmpeg-8.0.1"
make distclean 2>/dev/null || true
# Remove config cache to force reconfiguration
rm -f ffbuild/config.mak ffbuild/config.log 2>/dev/null || true

export PKG_CONFIG_ALLOW_CROSS=1
export PKG_CONFIG_PATH="$OPENH264_DIR/lib/pkgconfig:$PKG_CONFIG_PATH"
export PKG_CONFIG_LIBDIR=""
# Ensure PKG_CONFIG points to pkgconf (which provides pkg-config compatibility)
export PKG_CONFIG="pkg-config"

# Verify OpenH264 installation
if [ ! -f "$OPENH264_DIR/lib/libopenh264.a" ]; then
  echo "ERROR: OpenH264 library not found at $OPENH264_DIR/lib/libopenh264.a"
  exit 2
fi

if [ ! -f "$OPENH264_DIR/lib/pkgconfig/openh264.pc" ]; then
  echo "ERROR: OpenH264 pkg-config file not found at $OPENH264_DIR/lib/pkgconfig/openh264.pc"
  exit 2
fi

# Verify pkg-config can find OpenH264
echo "Verifying pkg-config setup..."
echo "PKG_CONFIG_PATH: $PKG_CONFIG_PATH"
echo "OpenH264 library: $OPENH264_DIR/lib/libopenh264.a"
echo "OpenH264 pkg-config: $OPENH264_DIR/lib/pkgconfig/openh264.pc"
if pkg-config --exists openh264 2>/dev/null; then
  VERSION=$(pkg-config --modversion openh264 2>/dev/null || echo "unknown")
  echo "✓ pkg-config found OpenH264: $VERSION"
  # Test the version requirement that FFmpeg uses
  if pkg-config --exists --atleast-version=1.3.0 openh264 2>/dev/null; then
    echo "✓ Version check passed (>= 1.3.0)"
  else
    echo "⚠ WARNING: Version check failed, but continuing..."
  fi
else
  echo "⚠ WARNING: pkg-config --exists failed, but library exists. Continuing..."
  echo "pkg-config file contents:"
  cat "$OPENH264_DIR/lib/pkgconfig/openh264.pc"
fi

mkdir -p "$BUILD_DIR"

# Build configure command
CONFIGURE_CMD=(
  ./configure
  --prefix="$BUILD_DIR"
  --pkg-config-flags="--static"
  --pkg-config="pkg-config"
  --enable-static
  --disable-shared
  --disable-programs
  --disable-doc
  --enable-avcodec
  --enable-avformat
  --enable-avutil
  --enable-swscale
  --enable-swresample
  --enable-zlib
  --disable-avdevice
  --disable-avfilter
  --disable-debug
  --disable-ffplay
  --disable-ffprobe
  --disable-gpl
  --disable-nonfree
  --arch="$FFMPEG_ARCH"
  --target-os=mingw32
  --cc="$CC"
  --enable-libopenh264
  --enable-encoder=libopenh264
  --enable-decoder=libopenh264
  --extra-cflags="-I$OPENH264_DIR/include"
  --extra-ldflags="-L$OPENH264_DIR/lib -static-libgcc -static-libstdc++"
  --extra-libs="-lopenh264 -lstdc++"
)

# Add cross-prefix only if needed and tools are available
if [ -n "$CROSS_PREFIX" ] && command -v "${CROSS_PREFIX}nm" >/dev/null 2>&1; then
  CONFIGURE_CMD+=(--cross-prefix="$CROSS_PREFIX")
  # Also set nm, ar, ranlib, strip to use cross-prefix versions
  export NM="${CROSS_PREFIX}nm"
  export AR="${CROSS_PREFIX}ar"
  export RANLIB="${CROSS_PREFIX}ranlib"
  export STRIP="${CROSS_PREFIX}strip"
else
  # Use regular tools (they should work for native Windows builds)
  echo "Using native MinGW-w64 tools (no cross-prefix)"
fi

echo "Configuring FFmpeg for windows/$ABI_DIR..."
echo "Using compiler: $CC"
echo "PKG_CONFIG_PATH: $PKG_CONFIG_PATH"
echo "Testing pkg-config before configure:"
pkg-config --exists --print-errors openh264 || echo "pkg-config test failed"
pkg-config --modversion openh264 || echo "version check failed"

"${CONFIGURE_CMD[@]}"

make -j"$CORES"
make install

# Copy into install dir with normalized pkg-config
mkdir -p "$INSTALL_DIR/lib" "$INSTALL_DIR/include" "$INSTALL_DIR/lib/pkgconfig"
cp -r "$BUILD_DIR/include/"* "$INSTALL_DIR/include/"
cp "$BUILD_DIR/lib/"*.a "$INSTALL_DIR/lib/"

# Copy pkg-config files if they exist
if [ -d "$BUILD_DIR/lib/pkgconfig" ]; then
  cp "$BUILD_DIR/lib/pkgconfig/"*.pc "$INSTALL_DIR/lib/pkgconfig/" 2>/dev/null || true
fi

# Normalize pkg-config files (Windows paths need special handling)
for PC_FILE in "$INSTALL_DIR/lib/pkgconfig/"*.pc; do
  if [ -f "$PC_FILE" ]; then
    # Convert Windows-style paths to Unix-style for pkg-config
    INSTALL_DIR_UNIX=$(echo "$INSTALL_DIR" | sed 's|^/\([a-zA-Z]\):|/\1|' | sed 's|\\|/|g')
    sed -i "s|^prefix=.*|prefix=${INSTALL_DIR_UNIX}|g" "$PC_FILE" || true
    sed -i "s|^exec_prefix=.*|exec_prefix=\\\${prefix}|g" "$PC_FILE" || true
    sed -i "s|^libdir=.*|libdir=\\\${prefix}/lib|g" "$PC_FILE" || true
    sed -i "s|^includedir=.*|includedir=\\\${prefix}/include|g" "$PC_FILE" || true
  fi
done

echo "FFmpeg installed: $INSTALL_DIR"

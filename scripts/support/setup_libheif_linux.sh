#!/bin/bash
set -euo pipefail

# Build libheif (+libde265) for Linux host (static).
# Installs into: third_party/libheif_install/linux/<arch>

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
THIRD_PARTY_DIR="$PROJECT_ROOT/third_party"
SOURCE_DIR="$THIRD_PARTY_DIR/sources"

mkdir -p "$SOURCE_DIR"

host_arch="$(uname -m)"
case "$host_arch" in
  x86_64) ABI_DIR="x86_64" ;;
  aarch64|arm64) ABI_DIR="arm64" ;;
  *) echo "Unsupported linux arch: $host_arch"; exit 2 ;;
esac

INSTALL_DIR="$THIRD_PARTY_DIR/libheif_install/linux/$ABI_DIR"
BUILD_DIR="$THIRD_PARTY_DIR/libheif_build_linux_$ABI_DIR"
DE265_INSTALL="$BUILD_DIR/libde265_install"

CORES="$(nproc 2>/dev/null || echo 4)"

if ! command -v cmake >/dev/null 2>&1; then
  echo "ERROR: cmake is required."
  exit 2
fi

cd "$SOURCE_DIR"

# libde265
if [ ! -d "libde265" ]; then
  echo "Cloning libde265..."
  git clone --depth 1 --branch v1.0.15 https://github.com/strukturag/libde265.git
fi

cd "$SOURCE_DIR/libde265"
rm -rf build_linux
mkdir -p build_linux
cd build_linux
cmake .. \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_INSTALL_PREFIX="$DE265_INSTALL" \
  -DCMAKE_POSITION_INDEPENDENT_CODE=ON \
  -DCMAKE_POLICY_VERSION_MINIMUM=3.5 \
  -DBUILD_SHARED_LIBS=OFF \
  -DENABLE_SDL=OFF \
  -DENABLE_DEC265=OFF \
  -DENABLE_ENCODER=OFF
make -j"$CORES"
make install

# libheif
LIBHEIF_VERSION="1.20.2"
cd "$SOURCE_DIR"
if [ ! -d "libheif-$LIBHEIF_VERSION" ]; then
  echo "Downloading libheif $LIBHEIF_VERSION..."
  curl -L "https://github.com/strukturag/libheif/releases/download/v$LIBHEIF_VERSION/libheif-$LIBHEIF_VERSION.tar.gz" | tar xz
fi

cd "$SOURCE_DIR/libheif-$LIBHEIF_VERSION"
rm -rf build_linux
mkdir -p build_linux
cd build_linux
cmake .. \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_INSTALL_PREFIX="$BUILD_DIR" \
  -DCMAKE_POSITION_INDEPENDENT_CODE=ON \
  -DBUILD_SHARED_LIBS=OFF \
  -DENABLE_PLUGIN_LOADING=OFF \
  -DWITH_AOM=OFF \
  -DWITH_DAV1D=OFF \
  -DWITH_RAV1E=OFF \
  -DWITH_X265=OFF \
  -DWITH_LIBDE265=ON \
  -DLIBDE265_INCLUDE_DIR="$DE265_INSTALL/include" \
  -DLIBDE265_LIBRARY="$DE265_INSTALL/lib/libde265.a" \
  -DWITH_EXAMPLES=OFF \
  -DWITH_TESTS=OFF \
  -DWITH_UNCOMPRESSED_CODEC=OFF \
  -DCMAKE_DISABLE_FIND_PACKAGE_AOM=ON \
  -DCMAKE_DISABLE_FIND_PACKAGE_libsharpyuv=ON \
  -DCMAKE_C_FLAGS="-fPIC" \
  -DCMAKE_CXX_FLAGS="-fPIC"

make -j"$CORES" heif
cmake --install . --component libheif 2>/dev/null || true

# Install layout + pkg-config for consumers
mkdir -p "$INSTALL_DIR/lib" "$INSTALL_DIR/include" "$INSTALL_DIR/lib/pkgconfig"

# Find and copy libheif.a (cmake build creates it in libheif/ subdirectory)
LIBHEIF_SOURCE=""
if [ -f "libheif/libheif.a" ]; then
  LIBHEIF_SOURCE="libheif/libheif.a"
elif [ -f "$BUILD_DIR/lib/libheif.a" ]; then
  LIBHEIF_SOURCE="$BUILD_DIR/lib/libheif.a"
else
  # Search for it
  LIBHEIF_SOURCE=$(find . -name "libheif.a" -type f 2>/dev/null | head -1)
  if [ -z "$LIBHEIF_SOURCE" ]; then
    echo "ERROR: libheif.a not found after build"
    exit 2
  fi
fi
cp -f "$LIBHEIF_SOURCE" "$INSTALL_DIR/lib/libheif.a"

cp -f "$DE265_INSTALL/lib/libde265.a" "$INSTALL_DIR/lib/" 2>/dev/null || true
cp -r "$BUILD_DIR/include/"* "$INSTALL_DIR/include/" 2>/dev/null || true

cat > "$INSTALL_DIR/lib/pkgconfig/libheif.pc" <<EOF
prefix=$INSTALL_DIR
exec_prefix=\${prefix}
libdir=\${exec_prefix}/lib
includedir=\${prefix}/include

Name: libheif
Description: HEIF image codec library
Version: 1.20.2
Libs: -L\${libdir} -lheif -lde265
Cflags: -I\${includedir}
Requires:
EOF

echo "libheif installed: $INSTALL_DIR"



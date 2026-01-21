#!/bin/bash
set -euo pipefail

# Build libheif (+libde265) for Windows host (static).
# Installs into: third_party/libheif_install/windows/x86_64
# Requires: MSYS2 with MinGW-w64 toolchain, cmake, make

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
THIRD_PARTY_DIR="$PROJECT_ROOT/third_party"
SOURCE_DIR="$THIRD_PARTY_DIR/sources"

mkdir -p "$SOURCE_DIR"

# Windows builds are typically x86_64
ABI_DIR="x86_64"

INSTALL_DIR="$THIRD_PARTY_DIR/libheif_install/windows/$ABI_DIR"
BUILD_DIR="$THIRD_PARTY_DIR/libheif_build_windows_$ABI_DIR"
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
rm -rf build_windows
mkdir -p build_windows
cd build_windows

# Configure for MinGW-w64
cmake .. \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_INSTALL_PREFIX="$DE265_INSTALL" \
  -DCMAKE_SYSTEM_NAME=Windows \
  -DCMAKE_C_COMPILER=x86_64-w64-mingw32-gcc \
  -DCMAKE_CXX_COMPILER=x86_64-w64-mingw32-g++ \
  -DCMAKE_POSITION_INDEPENDENT_CODE=ON \
  -DCMAKE_POLICY_VERSION_MINIMUM=3.5 \
  -DBUILD_SHARED_LIBS=OFF \
  -DENABLE_SDL=OFF \
  -DENABLE_DEC265=OFF \
  -DENABLE_ENCODER=OFF

# Use cmake --build instead of make for portability (works with any CMake generator)
cmake --build . --target de265 -j"$CORES"

# Manual install of libde265 (headers + library)
# CMake install may fail or not install headers correctly, so we do it manually
echo "Installing libde265..."
mkdir -p "$DE265_INSTALL/lib" "$DE265_INSTALL/include/libde265" "$DE265_INSTALL/lib/pkgconfig"

# Find and copy the library
FOUND_LIB=$(find . -maxdepth 4 -name "libde265.a" -type f 2>/dev/null | head -1)
if [ -z "$FOUND_LIB" ]; then
  echo "ERROR: libde265.a not found after build"
  exit 1
fi
cp -f "$FOUND_LIB" "$DE265_INSTALL/lib/libde265.a"

# Copy headers from source directory
# libde265 headers are typically in libde265/libde265/ in the source tree
if [ -d "../libde265/libde265" ]; then
  cp -r ../libde265/libde265/*.h "$DE265_INSTALL/include/libde265/" 2>/dev/null || true
fi
# Also check build directory (some headers might be generated)
if [ -d "libde265" ]; then
  cp -r libde265/*.h "$DE265_INSTALL/include/libde265/" 2>/dev/null || true
fi
# Verify at least one header was copied
if [ ! -f "$DE265_INSTALL/include/libde265/de265.h" ]; then
  echo "WARNING: de265.h not found, trying cmake install..."
  # Try cmake install as fallback
  cmake --install . 2>/dev/null || true
  # Check again after cmake install
  if [ ! -f "$DE265_INSTALL/include/libde265/de265.h" ]; then
    echo "ERROR: Failed to install libde265 headers"
    exit 1
  fi
fi

# Try cmake install as fallback for any missing headers
cmake --install . --component de265 2>/dev/null || cmake --install . 2>/dev/null || true

# libheif
LIBHEIF_VERSION="1.20.2"
cd "$SOURCE_DIR"
if [ ! -d "libheif-$LIBHEIF_VERSION" ]; then
  echo "Downloading libheif $LIBHEIF_VERSION..."
  curl -L "https://github.com/strukturag/libheif/releases/download/v$LIBHEIF_VERSION/libheif-$LIBHEIF_VERSION.tar.gz" | tar xz
fi

cd "$SOURCE_DIR/libheif-$LIBHEIF_VERSION"
rm -rf build_windows
mkdir -p build_windows
cd build_windows

# Configure for MinGW-w64
cmake .. \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_INSTALL_PREFIX="$BUILD_DIR" \
  -DCMAKE_SYSTEM_NAME=Windows \
  -DCMAKE_C_COMPILER=x86_64-w64-mingw32-gcc \
  -DCMAKE_CXX_COMPILER=x86_64-w64-mingw32-g++ \
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

# Use cmake --build instead of make for portability
cmake --build . --target heif -j"$CORES"

# Install libheif - try cmake install first, then manual copy
echo "Installing libheif..."
if cmake --install . --component libheif 2>/dev/null; then
  echo "✓ Installed via cmake component"
else
  echo "⚠ cmake --install failed, trying manual install"
fi

# Verify and find libheif.a (cmake install may place it in different locations)
FOUND_HEIF_LIB=""
if [ -f "$BUILD_DIR/lib/libheif.a" ]; then
  FOUND_HEIF_LIB="$BUILD_DIR/lib/libheif.a"
elif [ -f "libheif/libheif.a" ]; then
  FOUND_HEIF_LIB="libheif/libheif.a"
elif [ -f "../libheif/libheif.a" ]; then
  FOUND_HEIF_LIB="../libheif/libheif.a"
else
  # Search more broadly in build directory
  FOUND_HEIF_LIB=$(find . -name "libheif.a" -type f 2>/dev/null | head -1)
  if [ -z "$FOUND_HEIF_LIB" ]; then
    # Also check if it was built with a different name or in a subdirectory
    FOUND_HEIF_LIB=$(find . -name "*heif*.a" -type f 2>/dev/null | grep -v libde265 | head -1)
  fi
fi

if [ -z "$FOUND_HEIF_LIB" ]; then
  echo "ERROR: libheif.a not found after build"
  echo "Build directory contents:"
  find . -name "*.a" -type f 2>/dev/null | head -10
  exit 1
fi

echo "Found libheif.a at: $FOUND_HEIF_LIB"

# Install layout + pkg-config for consumers
mkdir -p "$INSTALL_DIR/lib" "$INSTALL_DIR/include" "$INSTALL_DIR/lib/pkgconfig"
cp -f "$FOUND_HEIF_LIB" "$INSTALL_DIR/lib/libheif.a"
cp -f "$DE265_INSTALL/lib/libde265.a" "$INSTALL_DIR/lib/" 2>/dev/null || true

# Copy headers
if [ -d "$BUILD_DIR/include/libheif" ]; then
  cp -r "$BUILD_DIR/include/libheif" "$INSTALL_DIR/include/" 2>/dev/null || true
elif [ -d "../libheif/api/libheif" ]; then
  cp -r ../libheif/api/libheif "$INSTALL_DIR/include/" 2>/dev/null || true
fi

# Verify libheif.a was copied
if [ ! -f "$INSTALL_DIR/lib/libheif.a" ]; then
  echo "ERROR: Failed to copy libheif.a to $INSTALL_DIR/lib/"
  exit 1
fi
echo "✓ Copied libheif.a to $INSTALL_DIR/lib/"

# Create pkg-config file (Windows paths need special handling)
INSTALL_DIR_UNIX=$(echo "$INSTALL_DIR" | sed 's|^/\([a-zA-Z]\):|/\1|' | sed 's|\\|/|g')
cat > "$INSTALL_DIR/lib/pkgconfig/libheif.pc" <<EOF
prefix=$INSTALL_DIR_UNIX
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

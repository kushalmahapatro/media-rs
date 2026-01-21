#!/bin/bash
set -e

# Directories
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
THIRD_PARTY_DIR="$PROJECT_ROOT/third_party"
GENERATED_DIR="$THIRD_PARTY_DIR/generated"
SOURCE_DIR="$GENERATED_DIR/sources"
IOS_INSTALL_DIR="$GENERATED_DIR/ffmpeg_install/ios"

mkdir -p "$IOS_INSTALL_DIR"
mkdir -p "$SOURCE_DIR"

# Number of cores for build
CORES=$(sysctl -n hw.ncpu 2>/dev/null || nproc 2>/dev/null || echo 4)

# Build OpenH264 first if not skipped (optional fallback for iOS)
if [ "$1" != "--skip-openh264" ]; then
    echo "=========================================="
    echo "Building OpenH264 for iOS (optional fallback for H.264 encoding)"
    echo "=========================================="
    
    # Note: OpenH264 for iOS would need a separate script
    # For now, we'll just note that VideoToolbox is the primary encoder
    echo "Note: VideoToolbox is the primary H.264 encoder for iOS."
    echo "OpenH264 support for iOS can be added if needed."
    echo ""
else
    echo "Skipping OpenH264 build (--skip-openh264 flag set)"
    echo ""
fi

# Download Source if needed
cd "$SOURCE_DIR"
if [ ! -d "ffmpeg-8.0.1" ]; then
    echo "Downloading FFmpeg 8.0.1..."
    curl -L https://ffmpeg.org/releases/ffmpeg-8.0.1.tar.bz2 | tar xj
fi

# Function to build for a specific target
build_ios() {
    ARCH=$1
    PLATFORM=$2 # "iphoneos" or "iphonesimulator"
    TARGET_DIR=$3
    
    echo "Building FFmpeg for iOS ($PLATFORM - $ARCH)..."
    
    SDK_PATH=$(xcrun --sdk $PLATFORM --show-sdk-path)
    # Force Xcode toolchain (avoid Homebrew clang/ld flags leaking into iOS builds)
    CC="$(xcrun --sdk $PLATFORM --find clang)"
    CXX="$(xcrun --sdk $PLATFORM --find clang++)"
    HOST_CC="$(xcrun --sdk macosx --find clang)"
    HOST_SDK="$(xcrun --sdk macosx --show-sdk-path)"
    # min version - iOS 16.0 required for __isPlatformVersionAtLeast used by VideoToolbox
    MIN_VERSION="-miphoneos-version-min=16.0" 
    if [ "$PLATFORM" == "iphonesimulator" ]; then
        MIN_VERSION="-mios-simulator-version-min=16.0"
    fi

    BUILD_DIR="$GENERATED_DIR/ffmpeg_build_ios_${PLATFORM}_${ARCH}"
    mkdir -p "$BUILD_DIR"
    
    cd "$SOURCE_DIR/ffmpeg-8.0.1"
    make distclean 2>/dev/null || true
    
    # LGPL Compliance: --disable-gpl and --disable-nonfree ensure LGPL license
    # Static linking is allowed under LGPL as long as GPL features are disabled
    CONFIGURE_FLAGS=(
        --prefix="$BUILD_DIR"
        --pkg-config-flags="--static"
        --enable-static
        --disable-shared
        --disable-programs
        --disable-doc
        --enable-swscale
        --enable-avcodec
        --enable-avformat
        --enable-avutil
        --enable-videotoolbox
        --enable-zlib
        --disable-avdevice
        --disable-avfilter
        --disable-debug
        --disable-ffplay
        --disable-ffprobe
        --disable-gpl
        --disable-nonfree
        --arch="$ARCH"
        --target-os=darwin
        --enable-cross-compile
        --sysroot="$SDK_PATH"
        --cc="$CC"
        --cxx="$CXX"
        --host-cc="$HOST_CC"
        --host-cflags="-isysroot $HOST_SDK"
        --host-ldflags="-isysroot $HOST_SDK"
        --extra-cflags="-arch $ARCH $MIN_VERSION"
        --extra-ldflags="-arch $ARCH $MIN_VERSION"
    )
    
    if [ "$ARCH" == "arm64" ]; then
        CONFIGURE_FLAGS+=(--enable-neon)
    elif [ "$ARCH" == "x86_64" ]; then
        # Avoid a hard dependency on nasm/yasm on fresh machines.
        CONFIGURE_FLAGS+=(--disable-x86asm)
    fi

    # Sanitize environment to prevent host (Homebrew) flags from breaking iOS link tests.
    # The failure mode we’re avoiding:
    #   ld: building for 'iOS', but linking in dylib .../libunwind.dylib built for 'macOS'
    env -u LDFLAGS -u CFLAGS -u CPPFLAGS -u CXXFLAGS -u LIBRARY_PATH -u CPATH -u C_INCLUDE_PATH -u CPLUS_INCLUDE_PATH \
      SDKROOT="$HOST_SDK" \
      ./configure "${CONFIGURE_FLAGS[@]}"
    make -j"$CORES"
    make install
    
    # Move to target dir
    mkdir -p "$TARGET_DIR/lib"
    mkdir -p "$TARGET_DIR/include"
    cp -r "$BUILD_DIR/include/"* "$TARGET_DIR/include/"
    cp "$BUILD_DIR/lib/"*.a "$TARGET_DIR/lib/"
    # pkgconfig?
    mkdir -p "$TARGET_DIR/lib/pkgconfig"
    cp "$BUILD_DIR/lib/pkgconfig/"*.pc "$TARGET_DIR/lib/pkgconfig/"
    
    # Fix pkgconfig prefix and paths
    for PC_FILE in "$TARGET_DIR/lib/pkgconfig/"*.pc; do
        sed -i '' "s|^prefix=.*|prefix=${TARGET_DIR}|g" "$PC_FILE"
        sed -i '' "s|^libdir=.*|libdir=\${prefix}/lib|g" "$PC_FILE"
        sed -i '' "s|^includedir=.*|includedir=\${prefix}/include|g" "$PC_FILE"
    done
}

# 1. Build for Device (arm64)
build_ios "arm64" "iphoneos" "$IOS_INSTALL_DIR/device"

# 2. Build for Simulator (arm64 + x86_64)
# We will NOT lipo them because Rust toolchain might prefer thin archives for checking.
# And we can select the correct path in build.dart.

# Build sim arm64
echo "Building Simulator arm64..."
SIM_ARM64_DIR="$IOS_INSTALL_DIR/simulator_arm64"
build_ios "arm64" "iphonesimulator" "$SIM_ARM64_DIR"

# Fix pkgconfig prefix and paths for sim_arm64
for PC_FILE in "$SIM_ARM64_DIR/lib/pkgconfig/"*.pc; do
    sed -i '' "s|^prefix=.*|prefix=${SIM_ARM64_DIR}|g" "$PC_FILE"
    sed -i '' "s|^libdir=.*|libdir=\${prefix}/lib|g" "$PC_FILE"
    sed -i '' "s|^includedir=.*|includedir=\${prefix}/include|g" "$PC_FILE"
done

# Build sim x86_64
echo "Building Simulator x86_64..."
SIM_X64_DIR="$IOS_INSTALL_DIR/simulator_x64"
build_ios "x86_64" "iphonesimulator" "$SIM_X64_DIR"

# Fix pkgconfig prefix and paths for sim_x86_64
for PC_FILE in "$SIM_X64_DIR/lib/pkgconfig/"*.pc; do
    sed -i '' "s|^prefix=.*|prefix=${SIM_X64_DIR}|g" "$PC_FILE"
    sed -i '' "s|^libdir=.*|libdir=\${prefix}/lib|g" "$PC_FILE"
    sed -i '' "s|^includedir=.*|includedir=\${prefix}/include|g" "$PC_FILE"
done

# Cleanup function ensures we don't need intermediate lipo steps.

echo "--------------------------------------------------------"
echo "FFmpeg iOS build complete (LGPL compliant)!"
echo "Device (arm64): $IOS_INSTALL_DIR/device"
echo "Simulator (arm64): $SIM_ARM64_DIR"
echo "Simulator (x86_64): $SIM_X64_DIR"
echo ""
echo "License: LGPL (GPL features disabled)"
echo "Compliance: --disable-gpl --disable-nonfree"
echo "--------------------------------------------------------"

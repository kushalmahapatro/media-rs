#!/bin/bash
set -e

# Build OpenH264 library for Android (BSD-licensed, LGPL-compatible)
# This provides H.264 encoding support for Android platforms

# Resolve repo root regardless of current working directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
THIRD_PARTY_DIR="$PROJECT_ROOT/third_party"
GENERATED_DIR="$THIRD_PARTY_DIR/generated"
ANDROID_INSTALL_DIR="$GENERATED_DIR/openh264_install/android"
SOURCE_DIR="$GENERATED_DIR/sources"

mkdir -p "$ANDROID_INSTALL_DIR"
mkdir -p "$SOURCE_DIR"

# NDK Support
if [ -z "$ANDROID_NDK_HOME" ]; then
    echo "Error: ANDROID_NDK_HOME is not set."
    echo "Please set it to your Android NDK location (e.g., export ANDROID_NDK_HOME=$HOME/Library/Android/sdk/ndk/27.3.13750724)"
    exit 1
fi

# Detect toolchain path (NDK 27+ may use different paths, including Apple Silicon)
TOOLCHAIN=""
if [ -d "$ANDROID_NDK_HOME/toolchains/llvm/prebuilt/darwin-x86_64" ]; then
    TOOLCHAIN="$ANDROID_NDK_HOME/toolchains/llvm/prebuilt/darwin-x86_64"
    if [[ "$(uname -m)" == "arm64" ]]; then
        echo "Running on Apple Silicon (arm64), using x86_64 NDK toolchain via Rosetta."
    fi
elif [ -d "$ANDROID_NDK_HOME/toolchains/llvm/prebuilt/darwin-arm64" ]; then
    TOOLCHAIN="$ANDROID_NDK_HOME/toolchains/llvm/prebuilt/darwin-arm64"
else
    # Try to find any prebuilt directory
    TOOLCHAIN=$(ls -d "$ANDROID_NDK_HOME/toolchains/llvm/prebuilt"/* 2>/dev/null | head -1)
    if [ -z "$TOOLCHAIN" ] || [ ! -d "$TOOLCHAIN" ]; then
        echo "Error: Could not find NDK toolchain in $ANDROID_NDK_HOME/toolchains/llvm/prebuilt/"
        exit 1
    fi
fi
echo "Using toolchain: $TOOLCHAIN"

# Number of cores
CORES=$(sysctl -n hw.ncpu 2>/dev/null || nproc 2>/dev/null || echo 4)

# Download OpenH264 source
cd "$SOURCE_DIR"
if [ ! -d "openh264" ]; then
    echo "Cloning OpenH264 repository..."
    git clone https://github.com/cisco/openh264.git
fi

cd openh264

# Make sure we're on a stable branch
git checkout master 2>/dev/null || true

build_openh264_android() {
    ARCH=$1
    ABI=$2
    API_LEVEL=$3
    CPU=$4
    
    echo "Building OpenH264 for Android $ABI (API $API_LEVEL)..."
    
    BUILD_DIR="$THIRD_PARTY_DIR/openh264_build_android_$ABI"
    INSTALL_ABI_DIR="$ANDROID_INSTALL_DIR/$ABI"
    
    mkdir -p "$BUILD_DIR"
    mkdir -p "$INSTALL_ABI_DIR"
    
    # Clean previous build (important to avoid cached paths)
    # Do a thorough clean to remove all cached object files and dependencies
    make clean 2>/dev/null || true
    # Remove all object files and dependency files that might have cached paths
    find . -name "*.o" -delete 2>/dev/null || true
    find . -name "*.d" -delete 2>/dev/null || true
    find . -name ".depend" -delete 2>/dev/null || true
    # Specifically remove cpu-features related files
    find codec/common/src -name "cpu-features.*" -delete 2>/dev/null || true
    
    # Setup toolchain based on architecture
    # OpenH264's Makefile uses: arm, arm64, x86, x86_64 (not aarch64 or armv7a)
    case $ARCH in
        aarch64)
            # OpenH264 expects "arm64" not "aarch64"
            OPENH264_ARCH="arm64"
            CC="$TOOLCHAIN/bin/aarch64-linux-android$API_LEVEL-clang"
            CXX="$TOOLCHAIN/bin/aarch64-linux-android$API_LEVEL-clang++"
            AR="$TOOLCHAIN/bin/llvm-ar"
            RANLIB="$TOOLCHAIN/bin/llvm-ranlib"
            STRIP="$TOOLCHAIN/bin/llvm-strip"
            EXTRA_CFLAGS="-march=armv8-a"
            ;;
        armv7a)
            # OpenH264 expects "arm" not "armv7a"
            OPENH264_ARCH="arm"
            CC="$TOOLCHAIN/bin/armv7a-linux-androideabi$API_LEVEL-clang"
            CXX="$TOOLCHAIN/bin/armv7a-linux-androideabi$API_LEVEL-clang++"
            AR="$TOOLCHAIN/bin/llvm-ar"
            RANLIB="$TOOLCHAIN/bin/llvm-ranlib"
            STRIP="$TOOLCHAIN/bin/llvm-strip"
            EXTRA_CFLAGS="-march=armv7-a -mfloat-abi=softfp -mfpu=vfpv3-d16"
            ;;
        x86)
            OPENH264_ARCH="x86"
            CC="$TOOLCHAIN/bin/i686-linux-android$API_LEVEL-clang"
            CXX="$TOOLCHAIN/bin/i686-linux-android$API_LEVEL-clang++"
            AR="$TOOLCHAIN/bin/llvm-ar"
            RANLIB="$TOOLCHAIN/bin/llvm-ranlib"
            STRIP="$TOOLCHAIN/bin/llvm-strip"
            EXTRA_CFLAGS="-march=i686 -mtune=intel -mssse3 -mfpmath=sse -m32"
            ;;
        x86_64)
            OPENH264_ARCH="x86_64"
            CC="$TOOLCHAIN/bin/x86_64-linux-android$API_LEVEL-clang"
            CXX="$TOOLCHAIN/bin/x86_64-linux-android$API_LEVEL-clang++"
            AR="$TOOLCHAIN/bin/llvm-ar"
            RANLIB="$TOOLCHAIN/bin/llvm-ranlib"
            STRIP="$TOOLCHAIN/bin/llvm-strip"
            # Remove -mtune=intel as clang doesn't recognize 'intel' as a valid CPU
            EXTRA_CFLAGS="-march=x86-64 -msse4.2 -mpopcnt -m64"
            # Disable assembly optimizations for x86_64 to avoid requiring nasm
            # This will use C implementations instead of assembly, which is fine for Android
            DISABLE_ASM="Yes"
            ;;
    esac
    
    # Build OpenH264 with Android toolchain
    # OpenH264 uses Makefile, we need to set environment variables
    # OpenH264's Makefile expects NDKROOT (not ANDROID_NDK_HOME)
    # Normalize the path (remove trailing slash) to avoid path resolution issues
    export NDKROOT="${ANDROID_NDK_HOME%/}"
    
    # Verify that cpu-features.c exists (required by OpenH264's Makefile)
    CPU_FEATURES_FILE="$NDKROOT/sources/android/cpufeatures/cpu-features.c"
    if [ ! -f "$CPU_FEATURES_FILE" ]; then
        echo "Error: Required file not found: $CPU_FEATURES_FILE"
        echo "This file is required by OpenH264's Android build."
        echo "Please ensure you have a complete Android NDK installation."
        return 1
    fi
    
    export CC
    export CXX
    export AR
    export RANLIB
    export STRIP
    export PREFIX="$BUILD_DIR"
    export OS=android
    export ARCH="$OPENH264_ARCH"  # Use OpenH264's expected architecture name (arm64, arm, x86, x86_64)
    export TARGET="android-$API_LEVEL"  # OpenH264 expects TARGET=android-21 format, not just "android"
    export NDKLEVEL="$API_LEVEL"  # Explicitly set NDKLEVEL to ensure compiler path is correct
    
    # Disable assembly for x86_64 if nasm is not available (avoids nasm dependency)
    if [ "${DISABLE_ASM:-No}" = "Yes" ]; then
        export USE_ASM=No
        echo "INFO: Disabling assembly optimizations for $ABI (nasm not required)"
    fi
    
    # Set CFLAGS and CXXFLAGS
    export CFLAGS="$EXTRA_CFLAGS -fPIC -I$TOOLCHAIN/sysroot/usr/include"
    export CXXFLAGS="$EXTRA_CFLAGS -fPIC -I$TOOLCHAIN/sysroot/usr/include"
    export LDFLAGS="-L$TOOLCHAIN/sysroot/usr/lib"
    
    # Build static library only (skip shared library and demo apps)
    # OpenH264's Makefile uses NDKROOT to find the toolchain
    # Use OPENH264_ARCH (arm64, arm, x86, x86_64) not our internal ARCH name
    # Build only the static library target to avoid shared library linking issues
    # Pass USE_ASM=No if we're disabling assembly
    MAKE_ARGS="OS=android ARCH=$OPENH264_ARCH TARGET=android-$API_LEVEL"
    if [ "${DISABLE_ASM:-No}" = "Yes" ]; then
        MAKE_ARGS="$MAKE_ARGS USE_ASM=No"
    fi
    if ! make -j"$CORES" $MAKE_ARGS libopenh264.a; then
        echo "Error: OpenH264 make failed for $ABI. See log above."
        return 1
    fi
    
    # Manually install static library and headers (skip make install to avoid shared library build)
    mkdir -p "$BUILD_DIR/lib"
    mkdir -p "$BUILD_DIR/include/wels"
    
    # Copy static library
    if [ -f "libopenh264.a" ]; then
        cp libopenh264.a "$BUILD_DIR/lib/"
    else
        echo "Error: libopenh264.a not found after build"
        return 1
    fi
    
    # Copy headers to wels subdirectory (FFmpeg expects wels/codec_api.h)
    if [ -d "codec/api/wels" ]; then
        cp -r codec/api/wels/*.h "$BUILD_DIR/include/wels/" 2>/dev/null || true
    fi
    
    # Create pkg-config file for FFmpeg
    mkdir -p "$BUILD_DIR/lib/pkgconfig"
    cat > "$BUILD_DIR/lib/pkgconfig/openh264.pc" <<EOF
prefix=$BUILD_DIR
exec_prefix=\${prefix}
libdir=\${exec_prefix}/lib
includedir=\${prefix}/include

Name: openh264
Description: OpenH264 is a codec library which supports H.264 encoding and decoding
Version: 2.6.0
Libs: -L\${libdir} -lopenh264 -lstdc++
Cflags: -I\${includedir}
EOF
    
    # Copy to install dir
    mkdir -p "$INSTALL_ABI_DIR/lib"
    mkdir -p "$INSTALL_ABI_DIR/include/wels"
    mkdir -p "$INSTALL_ABI_DIR/lib/pkgconfig"
    
    cp -r "$BUILD_DIR/include/"* "$INSTALL_ABI_DIR/include/" 2>/dev/null || true
    cp "$BUILD_DIR/lib/"*.a "$INSTALL_ABI_DIR/lib/" 2>/dev/null || true
    cp "$BUILD_DIR/lib/pkgconfig/"*.pc "$INSTALL_ABI_DIR/lib/pkgconfig/" 2>/dev/null || true
    
    # Update pkg-config file prefix for install dir
    if [ -f "$INSTALL_ABI_DIR/lib/pkgconfig/openh264.pc" ]; then
        sed -i '' "s|^prefix=.*|prefix=$INSTALL_ABI_DIR|g" "$INSTALL_ABI_DIR/lib/pkgconfig/openh264.pc"
    fi
    
    # If OpenH264 installs to different location, try common paths
    if [ ! -f "$INSTALL_ABI_DIR/lib/libopenh264.a" ]; then
        # Try to find the library
        find "$BUILD_DIR" -name "libopenh264.a" -exec cp {} "$INSTALL_ABI_DIR/lib/" \; 2>/dev/null || true
        find "$BUILD_DIR" -name "*.h" -path "*/codec/api/*" -exec cp {} "$INSTALL_ABI_DIR/include/" \; 2>/dev/null || true
    fi
    
    echo "OpenH264 for $ABI installed at $INSTALL_ABI_DIR"
}

API=21

# Build for common ABIs (skip armeabi-v7a as it's not required for modern devices)
echo "Building OpenH264 for Android ABIs..."
build_openh264_android "aarch64" "arm64-v8a" "$API" "armv8-a"
build_openh264_android "x86_64"  "x86_64"      "$API" "x86_64"
# build_openh264_android "armv7a"  "armeabi-v7a" "$API" "armv7-a" # Skipped - not required for modern devices

echo "--------------------------------------------------------"
echo "OpenH264 Android build complete!"
echo "Location: $ANDROID_INSTALL_DIR"
echo ""
echo "License: BSD-2-Clause (LGPL-compatible)"
echo "--------------------------------------------------------"


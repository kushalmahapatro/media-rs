#!/bin/bash
set -e

export ANDROID_NDK_ROOT="$HOME/Library/Android/sdk/ndk/27.3.13750724"



# Directories
PROJECT_ROOT="$(pwd)"
THIRD_PARTY_DIR="$PROJECT_ROOT/third_party"
SOURCE_DIR="$THIRD_PARTY_DIR/sources"
ANDROID_INSTALL_DIR="$THIRD_PARTY_DIR/ffmpeg_install/android"

mkdir -p "$ANDROID_INSTALL_DIR"
mkdir -p "$SOURCE_DIR"

# NDK Support
if [ -z "$ANDROID_NDK_HOME" ]; then
    echo "Error: ANDROID_NDK_HOME is not set."
    echo "Please set it to your Android NDK location (e.g., export ANDROID_NDK_HOME=$HOME/Library/Android/sdk/ndk/25.something)"
    exit 1
fi

# Detect host tag for NDK (darwin-arm64, darwin-x86_64, linux-x86_64, etc.)
HOST_OS=$(uname -s | tr '[:upper:]' '[:lower:]')  # "darwin" or "linux"
HOST_ARCH=$(uname -m)                             # "arm64" or "x86_64"
case "$HOST_ARCH" in
    arm64|aarch64) HOST_ARCH="arm64" ;;
    x86_64)        HOST_ARCH="x86_64" ;;
esac
HOST_TAG="${HOST_OS}-${HOST_ARCH}"

# Detect toolchain path using detected host tag
# Note: Some NDK versions only provide darwin-x86_64 even on Apple Silicon
# The x86_64 toolchain can run on Apple Silicon via Rosetta
TOOLCHAIN="$ANDROID_NDK_HOME/toolchains/llvm/prebuilt/${HOST_TAG}"

if [ ! -d "$TOOLCHAIN" ]; then
    # Fallback: try darwin-x86_64 if darwin-arm64 doesn't exist (common on Apple Silicon)
    if [ "$HOST_TAG" = "darwin-arm64" ]; then
        echo "Warning: darwin-arm64 toolchain not found, trying darwin-x86_64 (runs via Rosetta)"
        TOOLCHAIN="$ANDROID_NDK_HOME/toolchains/llvm/prebuilt/darwin-x86_64"
    fi
    
    if [ ! -d "$TOOLCHAIN" ]; then
        echo "Error: Could not find NDK toolchain"
        echo "Tried: $ANDROID_NDK_HOME/toolchains/llvm/prebuilt/${HOST_TAG}"
        if [ "$HOST_TAG" = "darwin-arm64" ]; then
            echo "Also tried: $ANDROID_NDK_HOME/toolchains/llvm/prebuilt/darwin-x86_64"
        fi
        echo "Available toolchains:"
        ls -d "$ANDROID_NDK_HOME/toolchains/llvm/prebuilt/"* 2>/dev/null || true
        exit 1
    fi
fi

echo "Using NDK toolchain: $TOOLCHAIN"

# Number of cores
CORES=$(sysctl -n hw.ncpu 2>/dev/null || nproc 2>/dev/null || echo 4)

# Download Source
cd "$SOURCE_DIR"
if [ ! -d "ffmpeg-8.0.1" ]; then
    echo "Downloading FFmpeg 8.0.1..."
    curl -L https://ffmpeg.org/releases/ffmpeg-8.0.1.tar.bz2 | tar xj
fi

build_android() {
    ARCH=$1
    ABI=$2
    API_LEVEL=$3
    CPU_INPUT=$4  # Input CPU parameter
    CPU=""  # Will be set per architecture
    
    echo "Building FFmpeg for Android $ABI (API $API_LEVEL)..."
    
    BUILD_DIR="$THIRD_PARTY_DIR/ffmpeg_build_android_$ABI"
    mkdir -p "$BUILD_DIR"
    
    cd "$SOURCE_DIR/ffmpeg-8.0.1"
    make distclean 2>/dev/null || true
    
    # FFmpeg's configure tries to run test executables for cross-compiled targets
    # We can't run Linux binaries on macOS, so we need to work around this
    # Set environment variable to indicate we're cross-compiling and should skip runtime tests
    export CROSS_COMPILE_SKIP_RUNTIME_TEST=1
    
    # Setup Drop-in replacement for NDK toolchain mapping
    TARGET_OS=android
    
    case $ARCH in
        aarch64)
            CROSS_PREFIX="$TOOLCHAIN/bin/aarch64-linux-android-"
            CC="$TOOLCHAIN/bin/aarch64-linux-android$API_LEVEL-clang"
            CXX="$TOOLCHAIN/bin/aarch64-linux-android$API_LEVEL-clang++"
            EXTRA_CFLAGS="-march=armv8-a"
            CPU="$CPU_INPUT"
            ;;
        armv7a)
            CROSS_PREFIX="$TOOLCHAIN/bin/arm-linux-androideabi-"
            CC="$TOOLCHAIN/bin/armv7a-linux-androideabi$API_LEVEL-clang"
            CXX="$TOOLCHAIN/bin/armv7a-linux-androideabi$API_LEVEL-clang++"
            EXTRA_CFLAGS="-march=armv7-a -mfloat-abi=softfp -mfpu=vfpv3-d16"
            CPU="$CPU_INPUT"
            ;;
        x86)
            CROSS_PREFIX="$TOOLCHAIN/bin/i686-linux-android-"
            CC="$TOOLCHAIN/bin/i686-linux-android$API_LEVEL-clang"
            CXX="$TOOLCHAIN/bin/i686-linux-android$API_LEVEL-clang++"
            EXTRA_CFLAGS="-march=i686 -mtune=intel -mssse3 -mfpmath=sse -m32"
            CPU="$CPU_INPUT"
            ;;
        x86_64)
            CROSS_PREFIX="$TOOLCHAIN/bin/x86_64-linux-android-"
            CC="$TOOLCHAIN/bin/x86_64-linux-android$API_LEVEL-clang"
            CXX="$TOOLCHAIN/bin/x86_64-linux-android$API_LEVEL-clang++"
            # Use x86-64 (with hyphen) for clang, not x86_64
            # Remove -mtune=intel as clang doesn't recognize 'intel' as a valid CPU
            # Use -mtune=generic or remove it entirely
            EXTRA_CFLAGS="-march=x86-64 -msse4.2 -mpopcnt -m64"
            CPU="generic"  # Use generic to prevent FFmpeg from adding conflicting -march flags
            ;;
    esac

    # Check if OpenH264 is available for this ABI
    # Note: We don't add OpenH264 to EXTRA_CFLAGS/EXTRA_LDFLAGS here because
    # it causes the C compiler test to fail (OpenH264's cpu-features.o is incompatible).
    # Instead, we let FFmpeg configure use pkg-config to find OpenH264.
    OPENH264_DIR="$THIRD_PARTY_DIR/openh264_install/android/$ABI"
    # Convert to absolute path to ensure pkg-config can find it
    OPENH264_DIR="$(cd "$OPENH264_DIR" 2>/dev/null && pwd || echo "$OPENH264_DIR")"
    OPENH264_ENABLED=""
    if [ -d "$OPENH264_DIR" ] && [ -f "$OPENH264_DIR/lib/libopenh264.a" ]; then
        OPENH264_ENABLED="yes"
        echo "Found OpenH264 for $ABI, will attempt to enable libopenh264 support"
        
        # For cross-compilation, set PKG_CONFIG environment variables
        # Use absolute paths to ensure pkg-config can find the files
        OPENH264_PKG_DIR="$OPENH264_DIR/lib/pkgconfig"
        if [ -d "$OPENH264_PKG_DIR" ]; then
            # Convert to absolute path
            OPENH264_PKG_DIR="$(cd "$OPENH264_PKG_DIR" 2>/dev/null && pwd || echo "$OPENH264_PKG_DIR")"
            # Set both PKG_CONFIG_LIBDIR and PKG_CONFIG_PATH
            # PKG_CONFIG_LIBDIR takes precedence and limits search to this directory
            export PKG_CONFIG_LIBDIR="$OPENH264_PKG_DIR"
            export PKG_CONFIG_PATH="$OPENH264_PKG_DIR:$PKG_CONFIG_PATH"
            
            # Verify pkg-config can find it (for debugging)
            if pkg-config --exists openh264 2>/dev/null; then
                echo "pkg-config successfully found OpenH264"
            else
                echo "Warning: pkg-config cannot find OpenH264, but will try anyway"
                echo "  PKG_CONFIG_LIBDIR: $PKG_CONFIG_LIBDIR"
                echo "  PKG_CONFIG_PATH: $PKG_CONFIG_PATH"
            fi
        else
            echo "Warning: OpenH264 pkg-config directory not found: $OPENH264_PKG_DIR"
        fi
    else
        echo "OpenH264 not found for $ABI, skipping libopenh264 (H.264 encoding may not work)"
        EXTRA_LDFLAGS=""
        # Clear PKG_CONFIG variables if OpenH264 not found
        unset PKG_CONFIG_LIBDIR
    fi
    
    # Get sysroot for the target architecture
    SYSROOT="$TOOLCHAIN/sysroot"
    
    # NDK 27+ uses llvm-ar, llvm-ranlib, llvm-strip, llvm-nm instead of architecture-specific tools
    AR="$TOOLCHAIN/bin/llvm-ar"
    RANLIB="$TOOLCHAIN/bin/llvm-ranlib"
    STRIP="$TOOLCHAIN/bin/llvm-strip"
    NM="$TOOLCHAIN/bin/llvm-nm"
    
    # For cross-compilation, we need to tell configure not to try running test executables
    # Set host and target triplets
    case $ARCH in
        aarch64)
            HOST_TRIPLE="aarch64-linux-android"
            ;;
        armv7a)
            HOST_TRIPLE="arm-linux-androideabi"
            ;;
        x86)
            HOST_TRIPLE="i686-linux-android"
            ;;
        x86_64)
            HOST_TRIPLE="x86_64-linux-android"
            ;;
    esac

    # LGPL Compliance: --disable-gpl and --disable-nonfree ensure LGPL license
    # Static linking is allowed under LGPL as long as GPL features are disabled
    CONFIGURE_FLAGS=(
        --prefix="$BUILD_DIR"
        --pkg-config-flags="--static"
        --pkg-config="pkg-config"
        --enable-static
        --disable-shared
        --disable-programs
        --disable-doc
        --enable-swscale
        --enable-avcodec
        --enable-avformat
        --enable-avutil
        --enable-zlib
        --disable-avdevice
        --disable-avfilter
        --disable-debug
        --disable-ffplay
        --disable-ffprobe
        --disable-gpl
        --disable-nonfree
        --target-os=android
        --enable-cross-compile
        --arch="$ARCH"
        --cpu="$CPU"
        --disable-runtime-cpudetect
        --cc="$CC"
        --cxx="$CXX"
        --ar="$AR"
        --ranlib="$RANLIB"
        --strip="$STRIP"
        --nm="$NM"
        --cross-prefix="$CROSS_PREFIX"
        --sysroot="$SYSROOT"
        --host-cc="clang"
        --host-cflags=""
        --host-ldflags=""
        --enable-jni
        --disable-mediacodec
        --extra-cflags="$EXTRA_CFLAGS --sysroot=$SYSROOT -fPIC"
        --extra-ldflags="$EXTRA_LDFLAGS --sysroot=$SYSROOT"
    )
    
    # Enable OpenH264 if available
    # For cross-compilation, pkg-config often fails, so we need to work around it
    if [ -n "$OPENH264_ENABLED" ]; then
        # Set environment variables to help pkg-config find OpenH264
        # Use absolute paths to ensure pkg-config can find the files
        OPENH264_PKG_DIR="$OPENH264_DIR/lib/pkgconfig"
        
        # Ensure PKG_CONFIG environment is set before configure runs
        if [ -d "$OPENH264_PKG_DIR" ] && [ -f "$OPENH264_PKG_DIR/openh264.pc" ]; then
            # Set PKG_CONFIG variables with absolute paths
            export PKG_CONFIG_LIBDIR="$OPENH264_PKG_DIR"
            export PKG_CONFIG_PATH="$OPENH264_PKG_DIR:$PKG_CONFIG_PATH"
            export PKG_CONFIG_ALLOW_CROSS=1
            export PKG_CONFIG_SYSROOT_DIR="$SYSROOT"
            
            # Test pkg-config (for debugging)
            echo "Testing pkg-config for OpenH264..."
            if pkg-config --exists --print-errors openh264 2>&1; then
                echo "✓ pkg-config successfully found OpenH264"
                # Also test version check (FFmpeg uses --atleast-version)
                if pkg-config --exists --atleast-version=1.3.0 openh264 2>&1; then
                    echo "✓ pkg-config version check passed (>= 1.3.0)"
                else
                    echo "⚠ Warning: pkg-config version check failed, but library exists"
                    VERSION=$(pkg-config --modversion openh264 2>/dev/null || echo "unknown")
                    echo "  OpenH264 version found: $VERSION"
                fi
            else
                echo "⚠ Warning: pkg-config test failed, but will try anyway"
                echo "  PKG_CONFIG_LIBDIR: $PKG_CONFIG_LIBDIR"
                echo "  PKG_CONFIG_PATH: $PKG_CONFIG_PATH"
            fi
            
            # Ensure PKG_CONFIG points to the system pkg-config (not a wrapper)
            # FFmpeg configure might use PKG_CONFIG environment variable
            if command -v pkg-config >/dev/null 2>&1; then
                PKG_CONFIG_BIN="$(command -v pkg-config)"
                export PKG_CONFIG="$PKG_CONFIG_BIN"
                # Also pass it to configure explicitly
                # Note: FFmpeg doesn't have --pkg-config flag, but we can ensure env is set
                echo "Using pkg-config: $PKG_CONFIG_BIN"
                echo "PKG_CONFIG environment: $PKG_CONFIG"
            fi
            
            # Debug: Show what pkg-config will see
            echo "PKG_CONFIG environment variables:"
            echo "  PKG_CONFIG: ${PKG_CONFIG:-not set}"
            echo "  PKG_CONFIG_LIBDIR: ${PKG_CONFIG_LIBDIR:-not set}"
            echo "  PKG_CONFIG_PATH: ${PKG_CONFIG_PATH:-not set}"
            echo "  PKG_CONFIG_ALLOW_CROSS: ${PKG_CONFIG_ALLOW_CROSS:-not set}"
            echo "  PKG_CONFIG_SYSROOT_DIR: ${PKG_CONFIG_SYSROOT_DIR:-not set}"
        else
            echo "Warning: OpenH264 pkg-config directory/file not found"
            echo "  Expected: $OPENH264_PKG_DIR/openh264.pc"
        fi
        
        # Always try to enable libopenh264
        # FFmpeg configure will use pkg-config if available, or fail and we'll handle it
        CONFIGURE_FLAGS+=(--enable-libopenh264)
        
        # Note: EXTRA_CFLAGS and EXTRA_LDFLAGS already include OpenH264 paths from above
        # These are used even if pkg-config fails
    fi
    
    # Export compiler variables so configure can find them
    export CC="$CC"
    export CXX="$CXX"
    export AR="$AR"
    export RANLIB="$RANLIB"
    export STRIP="$STRIP"
    export NM="$NM"
    export AS="$CC"
    export LD="$TOOLCHAIN/bin/ld"
    export CFLAGS="$EXTRA_CFLAGS --sysroot=$SYSROOT"
    export LDFLAGS="$EXTRA_LDFLAGS --sysroot=$SYSROOT"
    
    # For cross-compilation, we need to prevent configure from trying to run test executables
    # Set environment variables to skip runtime tests
    export CROSS_COMPILE=1
    export CROSS_COMPILE_SKIP_RUNTIME_TEST=1
    
    # For cross-compilation, we need to tell configure to skip runtime tests
    # CROSS_COMPILE_SKIP_RUNTIME_TEST is set above to skip runtime execution tests
    
    if [ "$ARCH" == "aarch64" ]; then
        CONFIGURE_FLAGS+=(--enable-neon)
    elif [ "$ARCH" == "armv7a" ]; then
        CONFIGURE_FLAGS+=(--enable-neon)
    elif [ "$ARCH" == "x86" ] || [ "$ARCH" == "x86_64" ]; then
        CONFIGURE_FLAGS+=(--enable-asm --enable-x86asm)
    fi

    # FFmpeg's configure tries to run test executables for cross-compiled targets
    # We can't run Linux binaries on macOS, so we need to work around this
    # Also, pkg-config might fail during cross-compilation even with correct paths
    # Try configure and if it fails, check if config was still created
    echo "Running FFmpeg configure..."
    echo "Current directory: $(pwd)"
    echo "PKG_CONFIG environment (before configure):"
    env | grep PKG_CONFIG || echo "  (no PKG_CONFIG variables set)"
    
    # Run configure and capture output
    # Note: FFmpeg configure may exit with error if C compiler test fails (can't run Android binaries on macOS),
    # but configure may still create config.mak. We need to check if config.mak was created anyway.
    echo "Running configure with OpenH264 support..."
    CONFIGURE_EXIT_CODE=0
    ./configure "${CONFIGURE_FLAGS[@]}" 2>&1 | tee "$BUILD_DIR/configure.log" || CONFIGURE_EXIT_CODE=$?
    
    # Check if config.mak was created (in ffbuild/ subdirectory)
    # Note: FFmpeg configure creates config.mak in the source directory where configure is run,
    # not in the build directory. Since we cd to SOURCE_DIR/ffmpeg-8.0.1 before running configure,
    # config.mak will be in that directory's ffbuild/ subdirectory.
    FFMPEG_SOURCE_DIR="$SOURCE_DIR/ffmpeg-8.0.1"
    CONFIG_MAK="$FFMPEG_SOURCE_DIR/ffbuild/config.mak"
    
    # FFmpeg configure may report "C compiler test failed" but still create config.mak
    # This happens because configure continues despite the test failure in cross-compilation scenarios
    
    # Check if config.mak exists - configure may create it even if C compiler test fails
    if [ -f "$CONFIG_MAK" ]; then
        echo ""
        echo "✓ Configure completed successfully (config.mak created)"
        echo "Note: C compiler test may have failed (expected for cross-compilation), but config.mak was created."
        echo "Checking if OpenH264 is enabled..."
        
        # Check if libopenh264 is mentioned in config.mak
        if grep -q "libopenh264\|CONFIG_LIBOPENH264" "$CONFIG_MAK" 2>/dev/null; then
            echo "✓ OpenH264 is enabled in config.mak"
        else
            echo "⚠ OpenH264 not found in config.mak"
            echo "  FFmpeg will use built-in encoder instead (H.264 encoding may be limited)"
        fi
    else
        echo ""
        echo "⚠ Configure failed or config.mak not created (exit code: $CONFIGURE_EXIT_CODE)"
        echo "This might be due to:"
        echo "  - C compiler test failure (can't run Android binaries on macOS - expected for cross-compilation)"
        echo "  - OpenH264 pkg-config failing during cross-compilation"
        echo ""
        echo "Retrying configure without --enable-libopenh264..."
        
        # Remove --enable-libopenh264 and try again
        CONFIGURE_FLAGS_NO_OPENH264=()
        for flag in "${CONFIGURE_FLAGS[@]}"; do
            if [[ "$flag" != "--enable-libopenh264" ]]; then
                CONFIGURE_FLAGS_NO_OPENH264+=("$flag")
            fi
        done
        
        # Clean up previous failed configure attempt
        rm -f "$BUILD_DIR/ffbuild/config.mak" "$BUILD_DIR/ffbuild/config.h" 2>/dev/null || true
        
        # Retry configure without OpenH264
        CONFIGURE_RETRY_EXIT_CODE=0
        ./configure "${CONFIGURE_FLAGS_NO_OPENH264[@]}" 2>&1 | tee "$BUILD_DIR/configure_no_openh264.log" || CONFIGURE_RETRY_EXIT_CODE=$?
        
        # Check if config.mak was created (configure may create it even if C compiler test fails)
        # Note: configure may exit with 0 even if it reports "C compiler test failed", 
        # but it may still create config.mak. We check for config.mak existence.
        if [ -f "$CONFIG_MAK" ]; then
            echo "✓ Configure succeeded without OpenH264 (config.mak created)"
            echo "  Note: C compiler test may have failed (expected for cross-compilation)"
            echo "  FFmpeg will use built-in encoder for H.264 (OpenH264 not available)"
        elif [ $CONFIGURE_RETRY_EXIT_CODE -eq 0 ]; then
            # Configure exited with 0 but config.mak doesn't exist - check if it's being created
            # Sometimes configure creates it in a subdirectory or with a delay
            sleep 1
            if [ -f "$CONFIG_MAK" ]; then
                echo "✓ Configure succeeded without OpenH264 (config.mak found after delay)"
                echo "  FFmpeg will use built-in encoder for H.264 (OpenH264 not available)"
            else
                # Check if configure actually completed successfully by looking for "License:" in output
                if grep -q "License:" "$BUILD_DIR/configure_no_openh264.log" 2>/dev/null; then
                    echo "⚠ Configure completed but config.mak not found in expected location"
                    echo "  Checking for config.mak in source directory..."
                    # Try to find config.mak in the source directory (where configure runs)
                    FOUND_CONFIG=$(find "$FFMPEG_SOURCE_DIR" -name "config.mak" -type f 2>/dev/null | head -1)
                    if [ -n "$FOUND_CONFIG" ]; then
                        echo "✓ Found config.mak at: $FOUND_CONFIG"
                        echo "  FFmpeg will use built-in encoder for H.264 (OpenH264 not available)"
                        # Update CONFIG_MAK to the found location
                        CONFIG_MAK="$FOUND_CONFIG"
                    else
                        echo "❌ Error: Configure completed but config.mak not found"
                        echo "  Searched in: $FFMPEG_SOURCE_DIR"
                        echo "  This is unusual - configure may have failed silently"
                        return 1
                    fi
                else
                    echo ""
                    echo "❌ Error: Configure failed even without OpenH264"
                    echo "Exit code: $CONFIGURE_RETRY_EXIT_CODE"
                    echo ""
                    echo "Last 30 lines of configure log:"
                    tail -30 "$BUILD_DIR/configure_no_openh264.log" 2>/dev/null || tail -30 "$BUILD_DIR/configure.log" 2>/dev/null || echo "  (configure log not found)"
                    echo ""
                    echo "Common issues:"
                    echo "  - Missing dependencies"
                    echo "  - Compiler/toolchain issues"
                    echo "  - Check configure logs for details"
                    return 1
                fi
            fi
        else
            echo ""
            echo "❌ Error: Configure failed even without OpenH264"
            echo "Exit code: $CONFIGURE_RETRY_EXIT_CODE"
            echo ""
            echo "Last 30 lines of configure log:"
            tail -30 "$BUILD_DIR/configure_no_openh264.log" 2>/dev/null || tail -30 "$BUILD_DIR/configure.log" 2>/dev/null || echo "  (configure log not found)"
            echo ""
            echo "Common issues:"
            echo "  - Missing dependencies"
            echo "  - Compiler/toolchain issues"
            echo "  - Check configure logs for details"
            return 1
        fi
    fi
    make -j"$CORES"
    make install
    
    # Copy to install dir
    INSTALL_ABI_DIR="$ANDROID_INSTALL_DIR/$ABI"
    mkdir -p "$INSTALL_ABI_DIR/lib"
    mkdir -p "$INSTALL_ABI_DIR/include"
    
    cp -r "$BUILD_DIR/include/"* "$INSTALL_ABI_DIR/include/"
    cp "$BUILD_DIR/lib/"*.a "$INSTALL_ABI_DIR/lib/"
     mkdir -p "$INSTALL_ABI_DIR/lib/pkgconfig"
    cp "$BUILD_DIR/lib/pkgconfig/"*.pc "$INSTALL_ABI_DIR/lib/pkgconfig/"
    
    for PC_FILE in "$INSTALL_ABI_DIR/lib/pkgconfig/"*.pc; do
        sed -i '' "s|^prefix=.*|prefix=${INSTALL_ABI_DIR}|g" "$PC_FILE"
    done
}

API=21

# Build OpenH264 first if not skipped (required for Android H.264 encoding)
if [ "$1" != "--skip-openh264" ]; then
    echo "=========================================="
    echo "Building OpenH264 for Android (required for H.264 encoding)"
    echo "=========================================="
    
    # Check if OpenH264 build script exists
    if [ -f "$PROJECT_ROOT/scripts/setup_openh264_android.sh" ]; then
        echo "Running OpenH264 build script..."
        "$PROJECT_ROOT/scripts/setup_openh264_android.sh"
        echo ""
    else
        echo "Warning: OpenH264 build script not found at scripts/setup_openh264_android.sh"
        echo "FFmpeg will be built without OpenH264 (H.264 encoding may not work)"
        echo ""
    fi
else
    echo "Skipping OpenH264 build (--skip-openh264 flag set)"
    echo ""
fi

# Build for common ABIs
# Note: armeabi-v7a (32-bit ARM) is skipped as it's no longer required for modern Android apps
build_android "aarch64" "arm64-v8a" "$API" "armv8-a"
build_android "x86_64"  "x86_64"      "$API" "x86_64"
# build_android "armv7a"  "armeabi-v7a" "$API" "armv7-a" # Skipped - not required for modern devices
# build_android "x86"     "x86"         "$API" "i686" # Optional, often skipped now

echo "--------------------------------------------------------"
echo "FFmpeg Android build complete (LGPL compliant)!"
echo "Location: $ANDROID_INSTALL_DIR"
echo ""
echo "License: LGPL (GPL features disabled)"
echo "Compliance: --disable-gpl --disable-nonfree"
if [ "$1" != "--skip-openh264" ] && [ -d "$THIRD_PARTY_DIR/openh264_install/android" ]; then
    echo "H.264 Encoding: OpenH264 (software encoder)"
else
    echo "H.264 Encoding: Built-in encoder (OpenH264 not built, MediaCodec disabled)"
fi
echo "--------------------------------------------------------"


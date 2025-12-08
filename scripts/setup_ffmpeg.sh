#!/bin/bash
set -e

# Directories
PROJECT_ROOT="$(pwd)"
THIRD_PARTY_DIR="$PROJECT_ROOT/third_party"
INSTALL_DIR="$THIRD_PARTY_DIR/ffmpeg_install"
SOURCE_DIR="$THIRD_PARTY_DIR/sources"

mkdir -p "$INSTALL_DIR"
mkdir -p "$SOURCE_DIR"

export PATH="$INSTALL_DIR/bin:$PATH"
export PKG_CONFIG_PATH="$INSTALL_DIR/lib/pkgconfig"

# Number of cores for build
CORES=$(sysctl -n hw.ncpu 2>/dev/null || nproc 2>/dev/null || echo 4)

# --- Clean Previous Build (optional but safer for license change) ---
# rm -rf "$INSTALL_DIR"

# --- 2. Build FFmpeg (Universal: arm64 + x86_64) ---

ARCHS=("arm64" "x86_64")
LIB_NAMES=("libavcodec" "libavformat" "libavutil" "libswresample" "libswscale")

# Check if universal libs already exist (simple check on one lib)
if [ -f "$INSTALL_DIR/lib/libavcodec.a" ]; then
    # Optional: Check if it's actually universal or just a leftover single arch
    ARCH_INFO=$(lipo -info "$INSTALL_DIR/lib/libavcodec.a")
    if [[ "$ARCH_INFO" == *"arm64"* ]] && [[ "$ARCH_INFO" == *"x86_64"* ]]; then
        echo "Universal FFmpeg already installed."
        exit 0
    fi
fi

# Build OpenH264 first if not skipped (optional fallback for macOS)
if [ "$1" != "--skip-openh264" ]; then
    echo "=========================================="
    echo "Building OpenH264 for macOS (optional fallback for H.264 encoding)"
    echo "=========================================="
    
    # Check if OpenH264 build script exists
    if [ -f "$PROJECT_ROOT/scripts/setup_openh264.sh" ]; then
        echo "Running OpenH264 build script..."
        "$PROJECT_ROOT/scripts/setup_openh264.sh"
        echo ""
    else
        echo "Note: OpenH264 build script not found. VideoToolbox will be used for H.264 encoding."
        echo ""
    fi
else
    echo "Skipping OpenH264 build (--skip-openh264 flag set)"
    echo ""
fi

# Download Source
cd "$SOURCE_DIR"
if [ ! -d "ffmpeg-8.0.1" ]; then
    echo "Downloading FFmpeg 8.0.1..."
    curl -L https://ffmpeg.org/releases/ffmpeg-8.0.1.tar.bz2 | tar xj
fi

for ARCH in "${ARCHS[@]}"; do
    echo "Building FFmpeg for $ARCH..."
    
    BUILD_DIR="$THIRD_PARTY_DIR/ffmpeg_build_$ARCH"
    mkdir -p "$BUILD_DIR"
    
    cd "$SOURCE_DIR/ffmpeg-8.0.1"
    
    # Cleanup previous config
    make distclean 2>/dev/null || true
    
    # Check if OpenH264 is available (check both possible install locations)
    OPENH264_DIR=""
    OPENH264_ENABLED=""
    # Check for architecture-specific build first
    if [ -f "$THIRD_PARTY_DIR/openh264_build_$ARCH/lib/libopenh264.a" ]; then
        OPENH264_DIR="$THIRD_PARTY_DIR/openh264_build_$ARCH"
        OPENH264_ENABLED="yes"
        echo "Found OpenH264 for $ARCH, enabling libopenh264 support"
    # Check for universal install
    elif [ -d "$THIRD_PARTY_DIR/openh264_install" ] && [ -f "$THIRD_PARTY_DIR/openh264_install/lib/libopenh264.a" ]; then
        OPENH264_DIR="$THIRD_PARTY_DIR/openh264_install"
        OPENH264_ENABLED="yes"
        echo "Found OpenH264, enabling libopenh264 support"
    fi
    
    # Configure flags
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
        --cc="clang -arch $ARCH" 
    )
    
    # Enable OpenH264 if available
    if [ -n "$OPENH264_ENABLED" ]; then
        CONFIGURE_FLAGS+=(--enable-libopenh264)
        CONFIGURE_FLAGS+=(--extra-cflags="-I$OPENH264_DIR/include")
        CONFIGURE_FLAGS+=(--extra-ldflags="-L$OPENH264_DIR/lib")
    fi
    
    # Enable/Disable assembly optimizations if needed (often auto-detected but explicit arch is safer)
    if [ "$ARCH" == "arm64" ]; then
        CONFIGURE_FLAGS+=(--enable-neon)
        # If host is x86_64, enable cross compile (but we are on arm64)
        if [ "$(uname -m)" != "arm64" ]; then
             CONFIGURE_FLAGS+=(--enable-cross-compile)
        fi
    elif [ "$ARCH" == "x86_64" ]; then
        CONFIGURE_FLAGS+=(--enable-asm --enable-x86asm)
         # If host is arm64, enable cross compile
        if [ "$(uname -m)" == "arm64" ]; then
             CONFIGURE_FLAGS+=(--enable-cross-compile)
        fi
    fi

    ./configure "${CONFIGURE_FLAGS[@]}"
    
    echo "Compiling for $ARCH..."
    make -j"$CORES"
    make install
done

# --- 3. Create Universal Binary (Lipo) ---
echo "Creating Universal Binaries..."
mkdir -p "$INSTALL_DIR/lib"
mkdir -p "$INSTALL_DIR/include"
mkdir -p "$INSTALL_DIR/lib/pkgconfig"

# Copy headers from arm64 (assuming they are compatible enough or identical for public API)
cp -r "$THIRD_PARTY_DIR/ffmpeg_build_arm64/include/"* "$INSTALL_DIR/include/"

# Merge Libs
for LIB in "${LIB_NAMES[@]}"; do
    echo "Lipo-ing $LIB.a..."
    lipo -create \
        "$THIRD_PARTY_DIR/ffmpeg_build_arm64/lib/$LIB.a" \
        "$THIRD_PARTY_DIR/ffmpeg_build_x86_64/lib/$LIB.a" \
        -output "$INSTALL_DIR/lib/$LIB.a"
done

# Merge pkg-config files?
# pkg-config files contain paths. Since we merge to a common install dir, we can just use one and update the prefix.
# However, libs might differ slightly? No, we merged them.
# Just copy from arm64 and ensure prefix is correct.
cp "$THIRD_PARTY_DIR/ffmpeg_build_arm64/lib/pkgconfig/"*.pc "$INSTALL_DIR/lib/pkgconfig/"

# Update prefix in pc files to point to INSTALL_DIR (in case it differs from build dir, which it does)
# Actually the build dir was ffmpeg_build_arm64. We need strict paths.
# We will use sed to replace the prefix line.
for PC_FILE in "$INSTALL_DIR/lib/pkgconfig/"*.pc; do
    # Replace prefix=/.../ffmpeg_build_arm64 with prefix=$INSTALL_DIR
    # Use | as delimiter to avoid path slashes issues
    sed -i '' "s|^prefix=.*|prefix=${INSTALL_DIR}|g" "$PC_FILE"
done

echo "Universal FFmpeg installed at $INSTALL_DIR"

echo "--------------------------------------------------------"
echo "FFmpeg static build complete (LGPL compliant)!"
echo "Location: $INSTALL_DIR"
echo "Include: $INSTALL_DIR/include"
echo "Lib: $INSTALL_DIR/lib"
echo ""
echo "License: LGPL (GPL features disabled)"
echo "Compliance: --disable-gpl --disable-nonfree"
echo "--------------------------------------------------------"

#!/bin/bash
# Setup environment variables for cargo commands
# Usage: source setup_env.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

export FFMPEG_DIR="$PROJECT_ROOT/third_party/ffmpeg_install"
export LIBHEIF_DIR="$PROJECT_ROOT/third_party/libheif_install/macos/universal"

# Detect architecture for OpenH264
ARCH=$(uname -m)
OPENH264_BUILD_DIR="$PROJECT_ROOT/third_party/openh264_build_$ARCH"

# Set OpenH264 directory if it exists
if [ -d "$OPENH264_BUILD_DIR" ]; then
    export OPENH264_DIR="$OPENH264_BUILD_DIR"
    # Add OpenH264 library path to RUSTFLAGS for linking (avoid duplicates)
    OPENH264_LIB_PATH="-L $OPENH264_BUILD_DIR/lib"
    if [ -z "$RUSTFLAGS" ]; then
        export RUSTFLAGS="$OPENH264_LIB_PATH"
    elif [[ "$RUSTFLAGS" != *"$OPENH264_BUILD_DIR/lib"* ]]; then
        export RUSTFLAGS="$RUSTFLAGS $OPENH264_LIB_PATH"
    fi
fi

# Prepend our pkg-config paths to any existing PKG_CONFIG_PATH (avoid duplicates)
LIBHEIF_PKG_CONFIG="$PROJECT_ROOT/third_party/libheif_install/macos/universal/lib/pkgconfig"
FFMPEG_PKG_CONFIG="$PROJECT_ROOT/third_party/ffmpeg_install/lib/pkgconfig"

# Remove our paths if they already exist to avoid duplicates
if [ -n "$PKG_CONFIG_PATH" ]; then
    PKG_CONFIG_PATH=$(echo "$PKG_CONFIG_PATH" | tr ':' '\n' | grep -v "^$LIBHEIF_PKG_CONFIG$" | grep -v "^$FFMPEG_PKG_CONFIG$" | tr '\n' ':' | sed 's/:$//')
fi

# Prepend our paths
if [ -z "$PKG_CONFIG_PATH" ]; then
    export PKG_CONFIG_PATH="$LIBHEIF_PKG_CONFIG:$FFMPEG_PKG_CONFIG"
else
    export PKG_CONFIG_PATH="$LIBHEIF_PKG_CONFIG:$FFMPEG_PKG_CONFIG:$PKG_CONFIG_PATH"
fi

# Also set PKG_CONFIG_LIBDIR (some build systems use this instead of PKG_CONFIG_PATH)
export PKG_CONFIG_LIBDIR="$LIBHEIF_PKG_CONFIG:$FFMPEG_PKG_CONFIG"

export PKG_CONFIG_ALLOW_SYSTEM_LIBS=1
export PKG_CONFIG_ALLOW_SYSTEM_CFLAGS=1

echo "Environment variables set:"
echo "  FFMPEG_DIR=$FFMPEG_DIR"
echo "  LIBHEIF_DIR=$LIBHEIF_DIR"
if [ -n "$OPENH264_DIR" ]; then
    echo "  OPENH264_DIR=$OPENH264_DIR"
fi
if [ -n "$RUSTFLAGS" ]; then
    echo "  RUSTFLAGS=$RUSTFLAGS"
fi
echo "  PKG_CONFIG_PATH=$PKG_CONFIG_PATH"


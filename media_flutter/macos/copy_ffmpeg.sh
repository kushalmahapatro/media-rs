#!/bin/bash
# Auto-copy FFmpeg binaries to macOS app bundle
# Called automatically by CocoaPods after compilation

set -e

# Get the app bundle path (passed by Podspec)
APP_BUNDLE="$1"

if [ -z "$APP_BUNDLE" ] || [ ! -d "$APP_BUNDLE" ]; then
    echo "⚠️  App bundle not found: $APP_BUNDLE"
    echo "   This script is called automatically by CocoaPods"
    exit 0  # Don't fail the build
fi

# Determine architecture
ARCH=$(uname -m)
if [ "$ARCH" = "arm64" ]; then
    FFMPEG_ARCH="darwin-arm64"
else
    FFMPEG_ARCH="darwin-x64"
fi

# Try to find FFmpeg in multiple locations
FFMPEG_SRC=""
FFPROBE_SRC=""

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Prefer fat universal binaries when present (matches Flutter default universal macOS .app).
UNIV_DEV="$SCRIPT_DIR/../../media_dart/native/ffmpeg/darwin-universal"
if [ -f "$UNIV_DEV/ffmpeg" ] && [ -f "$UNIV_DEV/ffprobe" ]; then
    FFMPEG_SRC="$UNIV_DEV/ffmpeg"
    FFPROBE_SRC="$UNIV_DEV/ffprobe"
    echo "📦 Found FFmpeg (universal): $UNIV_DEV"
fi

# Location 1: In media_dart package (development mode) — thin arch slice
DEV_PATH="$SCRIPT_DIR/../../media_dart/native/ffmpeg/$FFMPEG_ARCH"
if [ -z "$FFMPEG_SRC" ] && [ -f "$DEV_PATH/ffmpeg" ] && [ -f "$DEV_PATH/ffprobe" ]; then
    FFMPEG_SRC="$DEV_PATH/ffmpeg"
    FFPROBE_SRC="$DEV_PATH/ffprobe"
    echo "📦 Found FFmpeg in development mode: $DEV_PATH"
fi

# Location 2: In pub cache (look for media_dart package)
if [ -z "$FFMPEG_SRC" ]; then
    PUB_CACHE="${PUB_CACHE:-$HOME/.pub-cache}"
    MEDIA_DART_PKG=$(find "$PUB_CACHE/hosted" -type d -name "media_dart-*" 2>/dev/null | sort -V | tail -1)
    if [ -n "$MEDIA_DART_PKG" ]; then
        PUB_UNIV="$MEDIA_DART_PKG/native/ffmpeg/darwin-universal"
        if [ -f "$PUB_UNIV/ffmpeg" ] && [ -f "$PUB_UNIV/ffprobe" ]; then
            FFMPEG_SRC="$PUB_UNIV/ffmpeg"
            FFPROBE_SRC="$PUB_UNIV/ffprobe"
            echo "📦 Found FFmpeg (universal) in pub cache: $PUB_UNIV"
        else
            PUB_PATH="$MEDIA_DART_PKG/native/ffmpeg/$FFMPEG_ARCH"
            if [ -f "$PUB_PATH/ffmpeg" ] && [ -f "$PUB_PATH/ffprobe" ]; then
                FFMPEG_SRC="$PUB_PATH/ffmpeg"
                FFPROBE_SRC="$PUB_PATH/ffprobe"
                echo "📦 Found FFmpeg in pub cache: $PUB_PATH"
            fi
        fi
    fi
fi

# Location 3: In user's project
if [ -z "$FFMPEG_SRC" ]; then
    USER_PATH="$SRCROOT/../native/ffmpeg/$FFMPEG_ARCH"
    if [ -f "$USER_PATH/ffmpeg" ] && [ -f "$USER_PATH/ffprobe" ]; then
        FFMPEG_SRC="$USER_PATH/ffmpeg"
        FFPROBE_SRC="$USER_PATH/ffprobe"
        echo "📦 Found FFmpeg in user project: $USER_PATH"
    fi
fi

# If still not found, warn and exit (don't fail the build)
if [ -z "$FFMPEG_SRC" ] || [ ! -f "$FFMPEG_SRC" ]; then
    echo "⚠️  FFmpeg not found in any location:"
    echo "   - Development: $SCRIPT_DIR/../../media_dart/native/ffmpeg/$FFMPEG_ARCH/"
    echo "   - Pub cache: $PUB_CACHE/hosted/*/media_dart-*/native/ffmpeg/$FFMPEG_ARCH/"
    echo "   - User project: native/ffmpeg/$FFMPEG_ARCH/"
    echo ""
    echo "   Run this to download FFmpeg:"
    echo "   dart run media_dart:hook/build.dart"
    exit 0  # Don't fail the build
fi

# Target: app Contents/Frameworks (Flutter layout; Rust bundled_tools also checks here)
TARGET_DIR="$APP_BUNDLE/Contents/Frameworks"
mkdir -p "$TARGET_DIR"

cp "$FFMPEG_SRC" "$TARGET_DIR/ffmpeg"
cp "$FFPROBE_SRC" "$TARGET_DIR/ffprobe"
chmod +x "$TARGET_DIR/ffmpeg" "$TARGET_DIR/ffprobe"

# Drop local symbols only (smaller on disk; keeps exports for dynamic loader).
if command -v strip >/dev/null 2>&1; then
    strip -x "$TARGET_DIR/ffmpeg" "$TARGET_DIR/ffprobe" 2>/dev/null || true
fi

echo "✅ Copied FFmpeg to $TARGET_DIR"
echo "   - ffmpeg: $(du -h "$TARGET_DIR/ffmpeg" | cut -f1)"
echo "   - ffprobe: $(du -h "$TARGET_DIR/ffprobe" | cut -f1)"

# bundled_tools resolves ../.. from Versions/A to Contents/Frameworks/; a second copy
# under media.framework/Versions/A duplicates ~100MB+ in the .app — do not copy there.

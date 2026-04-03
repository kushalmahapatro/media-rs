#!/bin/bash
# Post-build script to copy FFmpeg to macOS app bundle
# This should be run after `flutter build macos`

set -e

# Get the app bundle path
APP_BUNDLE="${1:-build/macos/Build/Products/Release/media.app}"

if [ ! -d "$APP_BUNDLE" ]; then
    echo "Error: App bundle not found at $APP_BUNDLE"
    echo "Usage: $0 [path/to/MyApp.app]"
    exit 1
fi

# Determine architecture
ARCH=$(uname -m)
if [ "$ARCH" = "arm64" ]; then
    FFMPEG_DIR="native/ffmpeg/darwin-arm64"
else
    FFMPEG_DIR="native/ffmpeg/darwin-x64"
fi

# Source FFmpeg binaries
FFMPEG_SRC="$FFMPEG_DIR/ffmpeg"
FFPROBE_SRC="$FFMPEG_DIR/ffprobe"

if [ ! -f "$FFMPEG_SRC" ] || [ ! -f "$FFPROBE_SRC" ]; then
    echo "Error: FFmpeg binaries not found in $FFMPEG_DIR"
    echo "Run 'dart run hook/build.dart' first to download them."
    exit 1
fi

# Target directory (Frameworks, same as libmedia.dylib)
TARGET_DIR="$APP_BUNDLE/Contents/Frameworks"
mkdir -p "$TARGET_DIR"

# Copy binaries
cp "$FFMPEG_SRC" "$TARGET_DIR/ffmpeg"
cp "$FFPROBE_SRC" "$TARGET_DIR/ffprobe"
chmod +x "$TARGET_DIR/ffmpeg" "$TARGET_DIR/ffprobe"

echo "✅ Copied ffmpeg/ffprobe to $TARGET_DIR"
echo "   - ffmpeg: $(ls -lh "$TARGET_DIR/ffmpeg" | awk '{print $5}')"
echo "   - ffprobe: $(ls -lh "$TARGET_DIR/ffprobe" | awk '{print $5}')"

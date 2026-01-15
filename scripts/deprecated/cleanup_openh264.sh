#!/bin/bash
# Cleanup script to remove unused OpenH264 build directories
# Keeps only the install directory that FFmpeg actually uses

set -e

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
THIRD_PARTY_DIR="$PROJECT_ROOT/third_party"

echo "=========================================="
echo "Cleaning up unused OpenH264 directories"
echo "=========================================="
echo ""

# Directories to remove (build directories - temporary)
BUILD_DIRS=(
    "$THIRD_PARTY_DIR/openh264_build_android_arm64-v8a"
    "$THIRD_PARTY_DIR/openh264_build_android_x86_64"
    "$THIRD_PARTY_DIR/sources/third_party/openh264_build_android_arm64-v8a"
    "$THIRD_PARTY_DIR/sources/third_party/openh264_build_android_x86_64"
    "$THIRD_PARTY_DIR/sources/third_party/openh264_install"
)

# Directories to keep (install directories - used by FFmpeg)
KEEP_DIRS=(
    "$THIRD_PARTY_DIR/openh264_install"
)

echo "Directories to REMOVE (build/temporary):"
for DIR in "${BUILD_DIRS[@]}"; do
    if [ -d "$DIR" ]; then
        SIZE=$(du -sh "$DIR" 2>/dev/null | cut -f1)
        echo "  - $DIR ($SIZE)"
    fi
done

echo ""
echo "Directories to KEEP (install - used by FFmpeg):"
for DIR in "${KEEP_DIRS[@]}"; do
    if [ -d "$DIR" ]; then
        SIZE=$(du -sh "$DIR" 2>/dev/null | cut -f1)
        echo "  - $DIR ($SIZE)"
    fi
done

echo ""
read -p "Do you want to remove the build directories? (y/N): " -n 1 -r
echo ""

if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo "Removing build directories..."
    for DIR in "${BUILD_DIRS[@]}"; do
        if [ -d "$DIR" ]; then
            echo "  Removing: $DIR"
            rm -rf "$DIR"
        fi
    done
    echo ""
    echo "✓ Cleanup complete!"
    echo ""
    echo "Remaining OpenH264 directories:"
    find "$THIRD_PARTY_DIR" -type d -name "*openh264*" 2>/dev/null | sort
else
    echo "Cleanup cancelled."
fi


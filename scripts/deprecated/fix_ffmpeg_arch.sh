#!/bin/bash
# Remove x86-64 object files from pre-built FFmpeg libraries for Android
# These object files are incompatible with ARM64 Android builds

set -e

FFMPEG_LIB_DIR="$1"
if [ -z "$FFMPEG_LIB_DIR" ]; then
    echo "Usage: $0 <ffmpeg_lib_dir>"
    exit 1
fi

LIBAVCODEC="$FFMPEG_LIB_DIR/libavcodec.a"
if [ ! -f "$LIBAVCODEC" ]; then
    echo "Error: $LIBAVCODEC not found"
    exit 1
fi

echo "Checking $LIBAVCODEC for incompatible object files..."

# List all object files
TEMP_DIR=$(mktemp -d)
trap "rm -rf $TEMP_DIR" EXIT

cd "$TEMP_DIR"
# Extract all files from the archive
ar x "$LIBAVCODEC" 2>/dev/null || {
    echo "Error: Failed to extract archive"
    exit 1
}

# Find x86-64 object files by checking each .o file
X86_64_FILES=""
for file in *.o; do
    if [ -f "$file" ]; then
        if file "$file" | grep -q "x86-64"; then
            X86_64_FILES="$X86_64_FILES $file"
        fi
    fi
done
X86_64_FILES=$(echo $X86_64_FILES | tr ' ' '\n' | grep -v '^$' | tr '\n' ' ')

if [ -z "$X86_64_FILES" ]; then
    echo "No x86-64 object files found in $LIBAVCODEC"
    exit 0
fi

echo "Found x86-64 object files:"
for file in $X86_64_FILES; do
    echo "  - $file"
done

# Create backup
BACKUP="$LIBAVCODEC.bak"
cp "$LIBAVCODEC" "$BACKUP"
echo "Created backup: $BACKUP"

# Remove x86-64 object files
for file in $X86_64_FILES; do
    echo "Removing x86-64 object file: $file"
    rm -f "$file"
done

# Repackage the library with remaining files
REMAINING_FILES=$(ls *.o 2>/dev/null | tr '\n' ' ')
if [ -z "$REMAINING_FILES" ]; then
    echo "Error: No object files remaining after removal"
    cp "$BACKUP" "$LIBAVCODEC"
    exit 1
fi

REMAINING_COUNT=$(echo $REMAINING_FILES | wc -w)
echo "Repackaging with $REMAINING_COUNT remaining object files..."
ar rcs "$LIBAVCODEC" $REMAINING_FILES
echo "✓ Repackaged $LIBAVCODEC without x86-64 object files"


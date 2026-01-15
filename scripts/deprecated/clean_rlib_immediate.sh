#!/bin/bash
# Script to clean incompatible object files from rust-ffmpeg-sys .rlib files
# This script monitors a directory and cleans .rlib files as soon as they're created

set -e

TARGET_DIR="$1"
if [ -z "$TARGET_DIR" ]; then
    echo "Usage: $0 <target_directory>"
    exit 1
fi

echo "Monitoring $TARGET_DIR for .rlib files to clean..."

# Find and clean existing .rlib files
find "$TARGET_DIR" -name "libffmpeg_sys_next*.rlib" -type f | while read rlib; do
    echo "Cleaning .rlib file: $rlib"
    
    # Create a temporary directory
    temp_dir=$(mktemp -d)
    trap "rm -rf $temp_dir" EXIT
    
    # Extract the .rlib
    cd "$temp_dir"
    if ar x "$rlib" 2>/dev/null; then
        # Remove all .o files (FFmpeg object files)
        rm -f *.o 2>/dev/null || true
        
        # Get list of remaining files
        remaining_files=$(ls -A 2>/dev/null | tr '\n' ' ' || echo "")
        
        if [ -n "$remaining_files" ]; then
            # Repackage the .rlib
            if ar rcs "$rlib" $remaining_files 2>/dev/null; then
                echo "✓ Cleaned .rlib file: $rlib"
            else
                echo "Warning: Failed to repackage .rlib: $rlib"
            fi
        else
            echo "Warning: No files remaining after cleaning .rlib: $rlib"
        fi
    else
        echo "Warning: Failed to extract .rlib: $rlib"
    fi
    
    cd - > /dev/null
    rm -rf "$temp_dir"
done

echo "Done cleaning .rlib files"


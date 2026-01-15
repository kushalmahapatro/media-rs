#!/bin/bash
# Script to clean incompatible object files from rust-ffmpeg-sys .rlib files
# This is needed because Cargo caches .rlib files that contain object files
# from previous BUILD-enabled builds, even when FFMPEG_DIR is set.

set -e

# Find all rust-ffmpeg-sys .rlib files
find "$1" -name "libffmpeg_sys_next*.rlib" -type f | while read rlib; do
    echo "Cleaning .rlib file: $rlib"
    
    # Create a temporary directory
    temp_dir=$(mktemp -d)
    trap "rm -rf $temp_dir" EXIT
    
    # Extract the .rlib
    cd "$temp_dir"
    ar x "$rlib"
    
    # Remove all .o files (FFmpeg object files)
    rm -f *.o
    
    # Repackage the .rlib
    ar rcs "$rlib" *
    
    echo "Cleaned .rlib file: $rlib"
done

echo "Done cleaning .rlib files"





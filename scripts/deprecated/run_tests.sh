#!/bin/bash
# Helper script to run Rust tests with proper environment variables

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Set up environment variables
export PKG_CONFIG_PATH="$PROJECT_ROOT/third_party/libheif_install/macos/universal/lib/pkgconfig:$PROJECT_ROOT/third_party/ffmpeg_install//lib/pkgconfig:$PKG_CONFIG_PATH"
export LIBHEIF_DIR="$PROJECT_ROOT/third_party/libheif_install/macos/universal"

# Change to native directory
cd "$PROJECT_ROOT/native"

# Run tests with arguments passed to this script
cargo test --package media --lib "$@" --nocapture


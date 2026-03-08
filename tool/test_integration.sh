#!/bin/bash
# Build Rust libs, clean Flutter, rebuild, and run compression estimate integration test.
# Usage: ./tool/test_integration.sh [platform] [test_video_path]
# Example: ./tool/test_integration.sh linux /path/to/sample.mp4

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PLATFORM="${1:-linux}"
TEST_VIDEO="${2:-}"

echo "=== Integration test: Build and test compression estimate ==="
echo "Platform: $PLATFORM"
echo "Test video: ${TEST_VIDEO:-<will search or skip>}"
echo ""

cd "$PROJECT_ROOT"

# 1. Build native libraries
echo ">>> Building Rust native libraries..."
dart run tool/setup.dart "--$PLATFORM" || {
  echo "Setup failed. Ensure FFmpeg and dependencies are available."
  exit 1
}

# 2. Clean Flutter build
echo ">>> Cleaning Flutter build..."
cd example
flutter clean

# 3. Get dependencies
echo ">>> Getting dependencies..."
flutter pub get

# 4. Run integration test
echo ">>> Running integration test..."
if [ -n "$TEST_VIDEO" ]; then
  export TEST_VIDEO_PATH="$TEST_VIDEO"
fi
flutter test integration_test/compression_estimate_test.dart

echo ""
echo "=== Integration test complete ==="

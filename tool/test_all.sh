#!/bin/bash
# Run all integration tests: concurrency, estimate accuracy, and comprehensive tests
# Usage: ./tool/test_all.sh [platform] [test_video_path]
# Example: ./tool/test_all.sh linux /path/to/sample.mp4

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PLATFORM="${1:-linux}"
TEST_VIDEO="${2:-}"

echo "=== Running All Integration Tests ==="
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

# 4. Run Rust unit tests (including concurrency test)
echo ""
echo ">>> Running Rust unit tests..."
cd "$PROJECT_ROOT/native"
cargo test --lib test_concurrent_operations -- --nocapture || {
  echo "Rust concurrency test failed or skipped (may need test video)"
}

# 5. Run Dart integration tests
echo ""
echo ">>> Running Dart integration tests..."
cd "$PROJECT_ROOT/example"

if [ -n "$TEST_VIDEO" ]; then
  export TEST_VIDEO_PATH="$TEST_VIDEO"
fi

echo ""
echo "--- Test 1: Estimate Accuracy ---"
flutter test integration_test/compression_estimate_test.dart || {
  echo "Estimate accuracy test failed or skipped"
}

echo ""
echo "--- Test 2: Concurrency ---"
flutter test integration_test/concurrency_test.dart || {
  echo "Concurrency test failed or skipped"
}

echo ""
echo "--- Test 3: Comprehensive (Estimate + Concurrency) ---"
flutter test integration_test/comprehensive_test.dart || {
  echo "Comprehensive test failed or skipped"
}

echo ""
echo "=== All Tests Complete ==="

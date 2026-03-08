# Integration Tests

This directory contains comprehensive integration tests for the media processing library, focusing on:

1. **Estimate Accuracy** - Verifies that compression estimates match actual results within ±15%
2. **Concurrency** - Tests that multiple FFmpeg operations can run concurrently
3. **Comprehensive** - Combined tests for both accuracy and concurrency

## Test Files

### 1. `compression_estimate_test.dart`
Tests estimate accuracy by comparing estimated vs actual compression size and duration.

**What it tests:**
- Compression estimate generation
- Actual compression execution
- Size accuracy (within ±15%)
- Duration accuracy (within ±15%)

**Run:**
```bash
cd example
flutter test integration_test/compression_estimate_test.dart
```

### 2. `concurrency_test.dart`
Tests concurrent operations to verify that FFmpeg operations can run in parallel.

**What it tests:**
- Thumbnail generation during compression (concurrent)
- Thumbnail generation during estimation (concurrent)
- Multiple thumbnails generated simultaneously
- Operations complete without blocking each other

**Run:**
```bash
cd example
flutter test integration_test/concurrency_test.dart
```

### 3. `comprehensive_test.dart`
Combines estimate accuracy and concurrency tests in a single comprehensive test.

**What it tests:**
- Estimate accuracy (±15% tolerance)
- Concurrent thumbnail generation during compression
- All operations complete successfully
- Performance metrics and timing

**Run:**
```bash
cd example
flutter test integration_test/comprehensive_test.dart
```

## Running All Tests

### Linux/macOS:
```bash
./tool/test_all.sh [platform] [test_video_path]
# Example:
./tool/test_all.sh linux /path/to/sample.mp4
```

### Windows:
```cmd
tool\test_all.bat [platform] [test_video_path]
REM Example:
tool\test_all.bat windows C:\path\to\sample.mp4
```

The script will:
1. Build Rust native libraries
2. Clean and rebuild Flutter
3. Run Rust unit tests (including concurrency test)
4. Run all Dart integration tests

## Prerequisites

1. **Test Video**: You need a test video file. The tests will look for:
   - `test_video.mp4`
   - `sample_1280x720.mp4`
   - `HDR.MOV`
   - `../native/HDR.MOV`
   - Or set `TEST_VIDEO_PATH` environment variable

2. **Setup**: Run setup script first:
   ```bash
   dart run tool/setup.dart --windows  # or --linux, --macos
   ```

## Expected Results

### Estimate Accuracy Test
- ✅ Estimated size within ±15% of actual size
- ✅ Estimated duration within ±15% of actual duration

### Concurrency Test
- ✅ All thumbnails generated successfully
- ✅ Thumbnails complete faster than serial execution
- ✅ Compression completes successfully
- ✅ No blocking between operations

### Comprehensive Test
- ✅ All of the above
- ✅ Detailed performance metrics printed

## Troubleshooting

**Test skipped**: If you see "Skipping: Set TEST_VIDEO_PATH...", provide a test video:
```bash
export TEST_VIDEO_PATH=/path/to/video.mp4
flutter test integration_test/comprehensive_test.dart
```

**FFmpeg not found**: Ensure FFmpeg is statically linked (in-process). The tests are designed for in-process FFmpeg, not external FFmpeg binaries.

**Concurrency not working**: If thumbnails take too long, check that:
- The mutex has been removed (should be removed in recent changes)
- FFmpeg is statically linked
- No other serialization is blocking operations

## Rust Unit Tests

The Rust codebase also includes a concurrency test:
```bash
cd native
cargo test --lib test_concurrent_operations -- --nocapture
```

This tests concurrent operations at the Rust level, verifying that:
- Compression and thumbnails can run in parallel threads
- All operations complete successfully
- No deadlocks or race conditions occur

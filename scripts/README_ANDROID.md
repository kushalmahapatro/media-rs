# Android FFmpeg Build Instructions

## Prerequisites

1. **Android NDK**: Download and install Android NDK (version 25 or later recommended)
   ```bash
   export ANDROID_NDK_HOME=$HOME/Library/Android/sdk/ndk/25.2.9519653
   # Or wherever your NDK is installed
   ```

2. **Verify NDK installation**:
   ```bash
   echo $ANDROID_NDK_HOME
   ls $ANDROID_NDK_HOME/toolchains/llvm/prebuilt/
   ```

## Build Steps

### Option 1: Build Everything (Recommended)

This will build OpenH264 first, then FFmpeg with OpenH264 support:

```bash
cd /Users/km/Projects/media-rs
./scripts/setup_ffmpeg_android.sh
```

### Option 2: Build Separately

1. **Build OpenH264 first** (for H.264 encoding support):
   ```bash
   ./scripts/setup_openh264_android.sh
   ```

2. **Build FFmpeg with OpenH264 support**:
   ```bash
   ./scripts/setup_ffmpeg_android.sh
   ```

   Or skip OpenH264 if you don't need H.264 encoding:
   ```bash
   ./scripts/setup_ffmpeg_android.sh --skip-openh264
   ```

## What Gets Built

### OpenH264
- **Location**: `third_party/openh264_install/android/`
- **ABIs**: `arm64-v8a`, `armeabi-v7a`, `x86_64`
- **License**: BSD-2-Clause (LGPL-compatible)

### FFmpeg
- **Location**: `third_party/ffmpeg_install/android/`
- **ABIs**: `arm64-v8a`, `armeabi-v7a`, `x86_64`
- **License**: LGPL (GPL features disabled)
- **H.264 Encoding**: Enabled via OpenH264 (if built)
- **Hardware Acceleration**: MediaCodec enabled

## Troubleshooting

### NDK Not Found
```bash
# Set ANDROID_NDK_HOME environment variable
export ANDROID_NDK_HOME=/path/to/your/ndk
```

### OpenH264 Build Fails
- OpenH264 uses a Makefile-based build system
- If the build fails, check that the NDK toolchain is correct
- You may need to adjust the build script for your specific NDK version

### FFmpeg Configure Fails
- Make sure OpenH264 is built first (if you want H.264 encoding)
- Check that all paths are correct
- Verify NDK toolchain paths

## License Compliance

- **FFmpeg**: Built with `--disable-gpl --disable-nonfree` (LGPL compliant)
- **OpenH264**: BSD-2-Clause license (LGPL-compatible)
- **MediaCodec**: Android system framework (no license concerns)

All builds are suitable for proprietary/closed-source distribution.


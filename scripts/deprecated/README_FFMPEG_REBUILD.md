# FFmpeg Rebuild Required for Android

## Problem

The pre-built FFmpeg library at `third_party/ffmpeg_install/android/arm64-v8a/lib/libavcodec.a` contains x86-64 object files (`libopenh264enc.o`, `libopenh264dec.o`, `libopenh264.o`) that are incompatible with Android ARM64 builds.

## Root Cause

The FFmpeg library was built for the wrong architecture (x86-64 instead of ARM64) or is incomplete.

## Solution

FFmpeg needs to be rebuilt for Android ARM64. Run:

```bash
./scripts/setup_ffmpeg_android.sh
```

This will rebuild FFmpeg for Android ARM64 with OpenH264 support.

## Temporary Workaround

If you need a quick fix, you can remove the incompatible object files:

```bash
ar d third_party/ffmpeg_install/android/arm64-v8a/lib/libavcodec.a libopenh264enc.o libopenh264dec.o libopenh264.o
```

However, this may cause undefined symbol errors if FFmpeg was built to depend on these files.





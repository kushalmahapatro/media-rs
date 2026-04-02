# GitHub Release Upload Instructions

## Files to Upload to GitHub Release v0.0.1

After the changes are merged, you need to upload the following files to the GitHub release:

### 1. Rust Library Files (Small, ~5-10 MB each)

These are the NEW unified builds with FFmpeg NOT embedded:

- `aarch64-apple-darwin.zip` - Contains libmedia.dylib (arm64, ~5-10 MB)
- `x86_64-apple-darwin.zip` - Contains libmedia.dylib (x86_64, ~5-10 MB)
- `x86_64-unknown-linux-gnu.zip` - Contains libmedia.so (~1.4 MB)
- `x86_64-pc-windows-gnu.zip` - Contains media.dll (~2.8 MB)

**How to generate:**
```bash
cd media_dart/rust/media
cargo build --release --target aarch64-apple-darwin
cargo build --release --target x86_64-apple-darwin
cross build --release --target x86_64-unknown-linux-gnu
cargo build --release --target x86_64-pc-windows-gnu
```

### 2. FFmpeg Binary Files (Large, ~50-70 MB each zipped)

- `aarch64-apple-darwin-ffmpeg.zip` (51 MB) - FFmpeg for Apple Silicon Macs
- `x86_64-apple-darwin-ffmpeg.zip` (51 MB) - FFmpeg for Intel Macs
- `x86_64-unknown-linux-gnu-ffmpeg.zip` (~140 MB) - FFmpeg for Linux
- `x86_64-pc-windows-gnu-ffmpeg.zip` (~140 MB) - FFmpeg for Windows

**Location:** `platform-builds/*.zip`

## Total Release Size

| Component | Size |
|-----------|------|
| Rust libraries (4 platforms) | ~20-30 MB total |
| FFmpeg binaries (4 platforms) | ~380 MB total |
| **Total** | **~400 MB** |

## How to Upload

1. Go to: https://github.com/kushalmahapatro/media-rs/releases
2. Edit release v0.0.1
3. Upload all 8 zip files
4. Save the release

## After Upload

The hook will automatically:
1. Download the small library for the target platform
2. Download the FFmpeg binaries for the same platform
3. Package them together in the Flutter app

## Result

Users get:
- **Small library** (~5-10 MB instead of 100-150 MB)
- **Separate FFmpeg** (loaded at runtime)
- **Same functionality** but faster downloads and smaller app updates

# macOS Plugin - Automatic FFmpeg Integration

## 🎯 Overview

The media_flutter macOS plugin automatically copies FFmpeg binaries to your app bundle during the build process. No manual steps required!

## 📋 Setup (One-Time)

### Step 1: Add Dependency

```yaml
# pubspec.yaml
dependencies:
  media_flutter: ^0.1.0
```

### Step 2: Download FFmpeg

Run once to download FFmpeg binaries:

```bash
dart run media_dart:hook/build.dart
```

This downloads FFmpeg to:
- `~/.pub-cache/hosted/pub.dev/media_dart-x.x.x/native/ffmpeg/darwin-arm64/` (arm64)
- `~/.pub-cache/hosted/pub.dev/media_dart-x.x.x/native/ffmpeg/darwin-x64/` (x86_64)

### Step 3: Build Your App

```bash
flutter build macos --release
```

**That's it!** The Podspec automatically copies FFmpeg to your app bundle. ✅

---

## 🔧 How It Works

### Automatic Copy via CocoaPods

The `media_flutter.podspec` includes a `script_phase` that runs after compilation:

```ruby
s.script_phases = [
  {
    :name => 'Copy FFmpeg Binaries',
    :script => 'bash "${PODS_TARGET_SRCROOT}/copy_ffmpeg.sh" "${BUILT_PRODUCTS_DIR}/${WRAPPER_NAME}" || true',
    :execution_position => :after_compile,
    :output_files => [
      '${BUILT_PRODUCTS_DIR}/${WRAPPER_NAME}/Contents/Frameworks/ffmpeg',
      '${BUILT_PRODUCTS_DIR}/${WRAPPER_NAME}/Contents/Frameworks/ffprobe',
    ],
  }
]
```

The copy script runs **`strip -x`** on the binaries and places them only under **`Contents/Frameworks/`** (Rust **`bundled_tools`** resolves them from there; duplicating inside **`media.framework`** was removed to save space).

### Smart FFmpeg Detection

The `copy_ffmpeg.sh` script searches for FFmpeg in multiple locations:

1. **Development mode**: `../../media_dart/native/ffmpeg/{arch}/`
   - For local development with both packages in the same repo

2. **Pub cache**: `~/.pub-cache/hosted/*/media_dart-*/native/ffmpeg/{arch}/`
   - For published packages from pub.dev

3. **User project**: `native/ffmpeg/{arch}/`
   - For manual FFmpeg placement

### Architecture Detection

The script automatically detects your Mac's architecture:
- **Apple Silicon** (M1/M2/M3): Uses `darwin-arm64` (22 MB)
- **Intel**: Uses `darwin-x64` (76 MB)

---

## 📁 Final App Structure

```
MyApp.app/
└── Contents/
    ├── Frameworks/
    │   ├── media.framework/          # Small Rust library (2.5 MB)
    │   ├── ffmpeg                     # FFmpeg binary (22-76 MB)
    │   └── ffprobe                    # FFprobe binary (22-76 MB)
    └── MacOS/
        └── MyApp                      # Flutter app executable
```

---

## 🐛 Troubleshooting

### FFmpeg Not Found Error

If you see:
```
⚠️ FFmpeg not found in any location
```

**Solution:** Run the download command:
```bash
dart run media_dart:hook/build.dart
```

### Build Works But App Crashes

If the app builds but crashes at runtime with "FFmpeg not found":

1. **Check if FFmpeg was copied:**
   ```bash
   ls -lh build/macos/Build/Products/Release/MyApp.app/Contents/Frameworks/
   # Should show: ffmpeg, ffprobe
   ```

2. **If missing, run the script manually:**
   ```bash
   cd media_flutter/macos
   ./copy_ffmpeg.sh ../../build/macos/Build/Products/Release/MyApp.app
   ```

3. **Clean and rebuild:**
   ```bash
   flutter clean
   flutter pub get
   flutter build macos --release
   ```

### Debug vs Release Builds

- The script copies FFmpeg to **both** Debug and Release builds
- If using `flutter run` (debug mode), FFmpeg should copy automatically
- If it doesn't, run the script manually for debug builds:
  ```bash
  ./media_flutter/macos/copy_ffmpeg.sh build/macos/Build/Products/Debug/media.app
  ```

---

## 📊 File Sizes

| Component | arm64 | x86_64 |
|-----------|-------|--------|
| libmedia.dylib | 2.5 MB | 2.5 MB |
| ffmpeg | 22 MB | 76 MB |
| ffprobe | 22 MB | 76 MB |
| **Total** | **~47 MB** | **~155 MB** |

**Note:** Much smaller than the old embedded approach (241 MB library)! 🎉

---

## 🚀 For Plugin Developers

### Testing Locally

When developing media_flutter:

```bash
cd media-rs/media_flutter/example
flutter build macos --release
# FFmpeg copies automatically from ../../media_dart/native/ffmpeg/
```

### Publishing

When publishing to pub.dev:
1. The script will automatically find FFmpeg in the pub cache
2. Users just need to run `dart run media_dart:hook/build.dart` once
3. The Podspec handles the rest

### Manual Script Usage

You can also run the script manually:

```bash
cd media_flutter/macos
./copy_ffmpeg.sh /path/to/MyApp.app
```

---

## 📝 Related Files

- `copy_ffmpeg.sh` - FFmpeg copy script (automatic via Podspec)
- `media_flutter.podspec` - CocoaPods plugin definition
- `Classes/MediaFlutterPlugin.swift` - Minimal plugin registration
- `../../media_dart/hook/build.dart` - FFmpeg download logic

---

**Need help?** Check the [MACOS_DUAL_MODE.md](../../MACOS_DUAL_MODE.md) guide for detailed architecture info.

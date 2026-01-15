# Setup (new machine)

This repo builds and uses **vendored native dependencies** under `third_party/*_install/*`.
The build hook (`media/hook/build.dart`) expects these directories to exist unless you override via env vars.
All build artifacts are generated under the **repo-root** `third_party/` directory (not under `scripts/`).

## One command (recommended)

### macOS host (builds macOS + iOS + Android)

```bash
export ANDROID_NDK_HOME="$HOME/Library/Android/sdk/ndk/<your-version>"
./setup_all.sh
```

#### iOS note (Xcode must be “activated” once)

If `flutter run` fails to **open Xcode** (LaunchServices errors like `_LSOpenURLsWithCompletionHandler ... error -10664`) or complains about licenses/components, run:

```bash
sudo xcode-select -s /Applications/Xcode_new.app/Contents/Developer
sudo xcodebuild -license accept
sudo xcodebuild -runFirstLaunch
open -a /Applications/Xcode_new.app
```

If Xcode was downloaded/unzipped manually and macOS blocks it, you may need to remove quarantine:

```bash
sudo xattr -dr com.apple.quarantine /Applications/Xcode_new.app
```

### Linux host (builds Linux + Android)

```bash
export ANDROID_NDK_HOME="/path/to/android/ndk"
./setup_all.sh
```

## Per platform (what gets produced)

- **macOS**
  - FFmpeg: `third_party/ffmpeg_install/`
  - libheif: `third_party/libheif_install/macos/universal`

- **iOS** (macOS host only)
  - FFmpeg: `third_party/ffmpeg_install/ios/{device,simulator_arm64,simulator_x64}`
  - libheif: `third_party/libheif_install/ios/{iphoneos,iphonesimulator}/{arm64,x86_64}`

- **Android**
  - OpenH264: `third_party/openh264_install/android/{arm64-v8a,x86_64}`
  - FFmpeg: `third_party/ffmpeg_install/android/{arm64-v8a,x86_64}`
  - libheif: `third_party/libheif_install/android/{arm64-v8a,x86_64}`

- **Linux**
  - OpenH264: `third_party/openh264_install/linux/{x86_64,arm64}`
  - FFmpeg: `third_party/ffmpeg_install/linux/{x86_64,arm64}`
  - libheif: `third_party/libheif_install/linux/{x86_64,arm64}`

- **Windows**
  - Vendored builds are not fully implemented yet.
  - Recommended workaround: install deps externally and set env overrides below.

### Windows entrypoint

Use `setup_all.bat` (requires MSYS2). Example:

```bat
set MSYS2_ROOT=C:\msys64
set ANDROID_NDK_HOME=C:\Android\ndk\27.3.13750724
setup_all.bat --android
```

## Env var overrides (useful for Windows / custom installs)

If you already have FFmpeg/libheif/OpenH264 built somewhere else, you can point the build hook at them:

- `MEDIA_RS_FFMPEG_DIR`: directory containing `include/` and `lib/` and `lib/pkgconfig/`
- `MEDIA_RS_LIBHEIF_DIR`: directory containing `include/` + `lib/` + `lib/pkgconfig/libheif.pc`
- `MEDIA_RS_OPENH264_DIR`: directory containing `include/` + `lib/` + `lib/pkgconfig/openh264.pc`

Example:

```bash
export MEDIA_RS_FFMPEG_DIR="/opt/media-deps/ffmpeg"
export MEDIA_RS_LIBHEIF_DIR="/opt/media-deps/libheif"
export MEDIA_RS_OPENH264_DIR="/opt/media-deps/openh264"
```



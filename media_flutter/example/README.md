# media example app

Demonstrates **`Media`** from **`media_flutter`**: **probe**, **single thumbnail** (save + preview), **preset transcode** with progress, **timeline** thumbnails, and **estimates** (compressed size + encode time with **`TranscodeCalibration`** after successful transcodes).

| | |
|--|--|
| **Pub package name** | `media_example` |
| **Android applicationId** | `com.example.media` |

## Features (lib/)

| Area | Notes |
|------|--------|
| **Picking media** | **Mobile:** `wechat_assets_picker` + `photo_manager` (same gallery UX on Android/iOS). **Desktop:** `file_picker`. |
| **Preview** | **`video_player`** for file / transcode output where used (`file_video_preview.dart`, `video_tab.dart`). |
| **Share** | **`share_plus`** (`media_example_actions.dart`). |
| **Transcode calibration** | On success, records wall time vs probe duration per **`VideoPreset`**; persists JSON under **`getApplicationSupportDirectory()`** (`transcode_calibration.json`). Improves **`estimateEncodeWallClock`** on repeat runs. |
| **Thumbnails** | `ThumbnailFormat` dropdown; **`Image.memory`** uses **`errorBuilder`** when preview decode fails (e.g. WebP on some Android/Impeller builds). |

## Run

From the **repository root** (Dart pub workspace + Melos):

```bash
dart pub get
dart run melos bootstrap   # optional after clone; pub get already links workspace
cd media_flutter/example
flutter run   # pick device: Android, iOS, macOS, Windows, Linux
```

Release builds from the root without changing directory:

```bash
dart run melos run build-example-apk --no-select
dart run melos run build-example-appbundle --no-select
dart run melos run build-example-ios --no-select
```

### Desktop (macOS / Linux / Windows)

1. **FFmpeg** — downloaded automatically by **`media_dart`**’s **`hook/build.dart`** when you build; **`ffmpeg`** / **`ffprobe`** land next to **`libmedia`** on desktop (including macOS). No manual script.
2. **Optional** manual Rust check: `cd ../../media_dart/rust/media && cargo build`.
3. **macOS:** if you do **not** use bundled tools and rely on **`PATH`**, sandboxed apps may need entitlements to spawn **`ffmpeg`** / **`ffprobe`**.

#### macOS: `NativeAssetsManifest` / `objective_c` build error

**`path_provider_foundation`** (via **`path_provider`**) depends on **`objective_c`**, which registers native assets. If **`flutter_assets/NativeAssetsManifest.json`** still lists **`objective_c`** but **`build/native_assets/macos/`** is empty or stale (common after a **`pub upgrade`** or switching Flutter SDKs), the Xcode **Thin Binary** step fails.

From **`media_flutter/example`** run **`flutter clean`**, then **`flutter pub get`**, then build again. If it persists, delete **`build/`** and **`.dart_tool/`** in the example and retry.

#### Smaller macOS downloads (DMG / PKG)

- **Architectures:** ship **both** **arm64** and **x86_64** when you support Apple Silicon and Intel. For **Flutter’s default universal** `.app`, publish **`universal-apple-darwin.zip`** + **`universal-apple-darwin-ffmpeg.zip`** and set **`macosUniversalPrebuild: true`** under **`hooks.user_defines.media_dart`** (see **[RELEASE_ASSETS.md](../../RELEASE_ASSETS.md)**).
- **One FFmpeg copy:** the plugin copies **`ffmpeg`** / **`ffprobe`** only into **`Contents/Frameworks/`** (not duplicated inside **`media.framework`**). Prefer **`native/ffmpeg/darwin-universal/`** when you have fat binaries; **`copy_ffmpeg.sh`** checks that first.
- **Strip:** the copy script runs **`strip -x`** on the bundled FFmpeg tools to shave redundant symbol table size.
- **Gallery plugins:** this example pulls **`wechat_assets_picker`** → **`photo_manager`** for mobile; those macOS pods add weight. A **desktop-only** product can drop that dependency and use **`file_picker`** only to shrink the app substantially.
- **Minimal FFmpeg:** replace binaries under **`media_dart/native/ffmpeg/`** or set **`MEDIA_FFMPEG_STATIC_BASE_URL`**, then regenerate **`{triple}-ffmpeg.zip`** with **`dart run media_cli collect-native … --archive-ffmpeg zip`** (see **[RELEASE_ASSETS.md](../../RELEASE_ASSETS.md)**).

### Android / iOS

Use **`flutter run`** as usual. Thumbnails and transcode use **platform APIs** (Media3 on Android when the plugin is linked), not FFmpeg.

The **example** `android/build.gradle.kts` applies **`resolutionStrategy`** for **`androidx.media3`** so it stays aligned with **`media_flutter`** when plugins like **`video_player`** pull Media3.

## Legal / FFmpeg

FFmpeg licensing applies to **desktop** bundles. See **[media_dart/README.md](../../media_dart/README.md)** and **[DOCUMENTATION.md](../../DOCUMENTATION.md)**.

## Docs

- **[DOCUMENTATION.md](../../DOCUMENTATION.md)** — full API and platform matrix  
- **[media_flutter/README.md](../README.md)** — plugin overview  
- **[media_dart/README.md](../../media_dart/README.md)** — hooks, FRB regeneration  

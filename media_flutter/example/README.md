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

### Android / iOS

Use **`flutter run`** as usual. Thumbnails and transcode use **platform APIs** (Media3 on Android when the plugin is linked), not FFmpeg.

The **example** `android/build.gradle.kts` applies **`resolutionStrategy`** for **`androidx.media3`** so it stays aligned with **`media_flutter`** when plugins like **`video_player`** pull Media3.

## Legal / FFmpeg

FFmpeg licensing applies to **desktop** bundles. See **[media_dart/README.md](../../media_dart/README.md)** and **[DOCUMENTATION.md](../../DOCUMENTATION.md)**.

## Docs

- **[DOCUMENTATION.md](../../DOCUMENTATION.md)** — full API and platform matrix  
- **[media_flutter/README.md](../README.md)** — plugin overview  
- **[media_dart/README.md](../../media_dart/README.md)** — hooks, FRB regeneration  

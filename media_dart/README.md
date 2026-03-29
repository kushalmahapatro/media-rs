# media_dart

Video **probe**, **thumbnails** (PNG / JPEG / WebP), **timeline thumbnail streams**, **H.264 transcode with progress**, and **pure Dart** size / encode-time **estimates** with optional **device calibration** (`TranscodeCalibration`). Native work is **Rust** behind **flutter_rust_bridge**.

**No Flutter SDK dependency** — usable from Dart CLI, servers, or any workflow that builds **native assets** (`hooks` + `code_assets`). **Android hardware transcode (Media3)** requires also adding [**media_flutter**](../media_flutter/) so Kotlin/JNI classes are on the classpath.

**Full API and platform behavior:** [DOCUMENTATION.md](../DOCUMENTATION.md).

## Package layout

| Path | Role |
|------|------|
| `lib/media_dart.dart` | Exports `Media`, FRB `api`, `RustLib`, `estimates.dart` |
| `lib/src/media_facade.dart` | `Media.init`, `probe`, thumbnails, timeline stream, transcode stream |
| `lib/src/estimates.dart` | `VideoPreset`, `estimateCompressedSize`, `estimateEncodeWallClock`, `TranscodeCalibration` |
| `lib/src/bindings/` | Generated FRB (`api.dart`, `frb_generated.dart`) — do not hand-edit |
| `hook/build.dart` | **Native hook:** Rust build + FFmpeg/ffprobe; **`localBuild: false`** + **`usePrebuild: true`** uses repo `platform-builds/`; both false → GitHub release zip |
| `../platform-builds/` | Optional prebuilts at **repo root** (gitignored); see [platform-builds/README.md](../platform-builds/README.md) |
| `../tool/native_build/` | Shared triple / FFmpeg helpers for the hook and **`media_cli`** (`package:media_native_build`) |
| `rust/media/` | FRB crate (`api.rs`, `platform/{android,ios,desktop}.rs`) |
| `rust/mediacodec/` | Android NDK MediaExtractor/Muxer helpers used by `platform/android.rs` |
| `flutter_rust_bridge.yaml` | Codegen config (`rust_root: rust/media`, `dart_output: lib/src/bindings/`) |

## Platforms

| Platform | Probe | Thumbnail / timeline | Transcode |
|----------|-------|----------------------|-----------|
| **Linux / macOS / Windows** | `ffprobe` subprocess | `ffmpeg` subprocess | FFmpeg H.264 + AAC (x264 / platform encoders per `desktop.rs`) |
| **Android** | `MediaExtractor` + JNI (`MediaFormat`); **display** width/height with `rotation-degrees` swap | `MediaMetadataRetriever` + `Bitmap.compress` / `BitmapFactory` for stills | **Media3 Transformer** if `media_flutter` + `MediaTranscoder` present (H.264/AAC, HDR→SDR tone map, rotation-aware scale); else NDK **remux** |
| **iOS** | AVFoundation | `AVAssetImageGenerator` | `AVAssetExportSession` |

Desktop **ffmpeg/ffprobe**: the **build hook** downloads binaries into gitignored `native/ffmpeg/<dir>/` (see `hook/build.dart`). **Linux and Windows** register **CodeAssets** beside `libmedia`. **macOS** copies tools into `rust/media/bundled/current/` and **embeds** them in `libmedia.dylib` so the Dart macOS native-asset pipeline is not given Mach-O executables as `CodeAsset`s.

## Prebuilt natives (`localBuild` + `usePrebuild`)

Apps can skip compiling Rust in the hook and copy from **`platform-builds/<os>/<triple>/`** at the repository root (next to `media_dart/`), or download the same layout from **GitHub releases** (`{triple}.zip` / `{triple}-debug.zip`).

In the **app** `pubspec.yaml` (not `media_dart`):

```yaml
hooks:
  user_defines:
    media_dart:
      localBuild: false
      usePrebuild: true   # platform-builds/; omit or false → GitHub release
```

Populate `platform-builds/` with the CLI (from repo root):

```bash
dart pub get
dart run melos run collect-native --no-select
```

Or from `tool/cli`: `dart run media_cli collect-native`.

Omit `localBuild` or set **`true`** for the default on-machine Rust build.

## Distribution builds ([Fastforge](https://pub.dev/packages/fastforge))

The Flutter example ships **`distribute_options.yaml`** and a **`fastforge`** dev dependency. From the **repo root**, Melos runs the same flow via **`media_cli dist`** (see root `pubspec.yaml` → `dist`, `dist-android`, `dist-apk`, `dist-aab`, `dist-ipa`, …).

From **`media_flutter/example/`**:

```bash
dart run fastforge:main release --name media-example --jobs android-apk
```

Or from **`tool/cli`**: `dart run media_cli dist --jobs android-apk`. Artifacts go under the repo as configured in `distribute_options.yaml`. See [fastforge.dev](https://fastforge.dev) for options and MSIX/IPA signing.

### Licensing (FFmpeg)

Prebuilt FFmpeg binaries are **LGPL/GPL**-relevant. Confirm compliance before shipping.

## Dependencies (pubspec)

- `flutter_rust_bridge`, `path`, `hooks`, `native_toolchain_rust`, `code_assets`, `archive` (Windows ARM64 zip), `logging`

## Regenerate FRB bindings

**Do not** manually edit `lib/src/bindings/frb_generated*.dart`, generated sections of `api.dart`, or `frb_bindings.h`.

After changing `rust/media/src/api.rs` (or `flutter_rust_bridge.yaml`):

```bash
cd packages/media/media_dart   # this package root
flutter_rust_bridge_codegen generate --config-file flutter_rust_bridge.yaml
```

(Equivalent: from `rust/media`, `flutter_rust_bridge_codegen generate --config-file ../../flutter_rust_bridge.yaml`.)

## Consume

**Dart-only** (CLI / server with native assets):

```yaml
dependencies:
  media_dart:
    path: packages/media/media_dart
```

**Flutter** (includes Android Media3 when you need re-encode, not just remux):

```yaml
dependencies:
  media_flutter:
    path: packages/media/media_flutter
```

Call **`Media.init()`** once before other APIs.

## Tests

```bash
cd packages/media/media_dart
dart test
```

## Example app

The Flutter sample lives under **`../media_flutter/example/`** (pub name `media`, Android applicationId `com.example.media`).

### Android JNI note

Flutter **native assets** often load `libmedia.so` without going through `JNI_OnLoad` for the Dart path. The crate uses **`libnativehelper`** + **`JNI_GetCreatedJavaVMs`** to attach; **`MediaTranscoder`** must load via the **app** class loader (**media_flutter** registers the Android library).

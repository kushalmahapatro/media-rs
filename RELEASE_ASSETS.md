# GitHub release assets (`libmedia` + FFmpeg)

This repo publishes **per–Rust-triple** zips that `media_dart`’s hook downloads from  
`https://github.com/kushalmahapatro/media-rs/releases/download/<version>/`.

Version string must match `const version` in `media_dart/hook/build.dart` (currently **`v0.1.2`**, aligned with the example app `version:`).

## What to upload

| Asset | Contents |
|--------|-----------|
| `{triple}.zip` | `platform-builds` layout: top-level folder `{triple}/` with `libmedia.dylib` / `.so` / `.dll` |
| `{triple}-ffmpeg.zip` | `triple/ffmpeg` (+ `ffprobe`, or `.exe` on Windows) — same prefix layout the hook expects |
| `universal-apple-darwin.zip` | Optional fat **`libmedia.dylib`** (arm64 + x86_64) for **Flutter’s default universal macOS app** |
| `universal-apple-darwin-ffmpeg.zip` | Optional fat **`ffmpeg`** / **`ffprobe`** for the same |

**iOS** (device + simulators; **`libmedia.dylib` only** — no FFmpeg zip; iOS uses system codecs / AVFoundation):

| Asset | Role |
|--------|------|
| `aarch64-apple-ios.zip` | Physical device (arm64) |
| `aarch64-apple-ios-sim.zip` | Apple Silicon simulator |
| `x86_64-apple-ios.zip` | Intel simulator (Rosetta / older Macs) |

**Android** (per-ABI **`libmedia.so`** plus **`ffmpeg`** / **`ffprobe`** inside the same `{triple}.zip`; hook copies the library; FFmpeg ships in the archive for local/prebuild layouts):

| Asset | Role |
|--------|------|
| `aarch64-linux-android.zip` | Phones / emulators (arm64) |
| `x86_64-linux-android.zip` | Emulator (x86_64) |
| `armv7-linux-androideabi.zip` | Older arm32 devices |

Thin macOS triples (still useful for CI, smaller per-arch downloads):

- `aarch64-apple-darwin.zip` / `aarch64-apple-darwin-ffmpeg.zip` — Apple Silicon  
- `x86_64-apple-darwin.zip` / `x86_64-apple-darwin-ffmpeg.zip` — Intel  

## One-shot: build + zip (from repo root)

Requires **Rust** targets installed, e.g.:

```bash
rustup target add aarch64-apple-darwin x86_64-apple-darwin
```

On a **Mac**, build both thin macOS slices, merge with **`lipo`**, write library + FFmpeg zips into `release-assets/<version>/`:

```bash
dart pub get
( cd tool/cli && dart run media_cli collect-native --package-root ../../media_dart \
  -t aarch64-apple-darwin -t x86_64-apple-darwin \
  --archive-format zip --archive-version v0.1.2 \
  --macos-universal --archive-ffmpeg zip )
```

Add Linux / Windows triples to the same command (repeat `-t …`) or run separate `collect-native` invocations, then re-run with **`--archive-only`** if you only need to refresh zips:

```bash
( cd tool/cli && dart run media_cli collect-native --package-root ../../media_dart \
  --archive-only --archive-format zip --archive-version v0.1.2 \
  --macos-universal --archive-ffmpeg zip )
```

Artifacts land under **`release-assets/v0.1.2/`** (override with `--archive-dir`).

Zip **existing** `platform-builds/ios/*` (after `melos run ios-lib` or a manual `collect-native` build):

```bash
( cd tool/cli && dart run media_cli collect-native --package-root ../../media_dart \
  --archive-only --archive-format zip --archive-version v0.1.2 \
  -t aarch64-apple-ios -t aarch64-apple-ios-sim -t x86_64-apple-ios )
```

Or: `dart run melos run release-assets-ios --no-select`.

**`dist/`** is for **Flutter/Fastforge app installers** (DMG/PKG from the example app), not these Rust prebuilt zips. Native release zips live only under **`release-assets/<tag>/`**.

### End-to-end (tests + GitHub zips + Android APK + 3× macOS DMG/PKG)

From the repo root (macOS, `gh` authenticated, Android NDK for Android steps):

```bash
bash tool/scripts/publish_media_rs_release.sh
```

Or: `dart run melos run publish-github-release`. Use `SKIP_NATIVE=1`, `SKIP_TESTS=1`, `SKIP_GH=1`, `SKIP_ANDROID_NATIVE=1`, `SKIP_IOS_NATIVE=1`, or `SKIP_ANDROID_APK=1` to skip steps.

## Upload with GitHub CLI

Install [GitHub CLI](https://cli.github.com/) (`gh auth login` once).

```bash
VER=v0.1.2
gh release create "$VER" --title "$VER" --notes "media-rs native + FFmpeg" --draft
gh release upload "$VER" "release-assets/$VER"/* --clobber
```

Or create the release in the web UI and **drag-and-drop** the same files.

## Flutter app: universal macOS prebuilts

In the **app** `pubspec.yaml` (same block as `localBuild` / `usePrebuild`):

```yaml
hooks:
  user_defines:
    media_dart:
      localBuild: false
      usePrebuild: false   # GitHub download
      macosUniversalPrebuild: true
```

Then the hook downloads **`universal-apple-darwin.zip`** and **`universal-apple-darwin-ffmpeg.zip`** for **both** arm64 and x64 macOS native-asset builds, matching a **universal** `flutter build macos` output.

If **`macosUniversalPrebuild`** is false (default), each architecture uses its thin triple (`aarch64-…` / `x86_64-…`).

## Slim / custom FFmpeg (desktop)

1. **Replace files locally** under `media_dart/native/ffmpeg/<subdir>/` (`darwin-arm64`, `darwin-x64`, `linux-*`, `windows-*`) with your minimal static builds, then run `collect-native` and **`--archive-ffmpeg zip`** so releases carry your binaries.

2. **Or** point downloads at your mirror (same asset names as [eugeneware/ffmpeg-static](https://github.com/eugeneware/ffmpeg-static) **or** your own layout after overriding):

```bash
export MEDIA_FFMPEG_STATIC_BASE_URL="https://github.com/you/your-ffmpeg/releases/download/v1"
dart run media_cli collect-native -t aarch64-apple-darwin ...
```

Hook / `pub get` builds that call `mediaEnsureFfmpegDownloadedForRustTriple` also honor **`MEDIA_FFMPEG_STATIC_BASE_URL`** when fetching into `native/ffmpeg/`.

## Melos

From repo root:

```bash
dart run melos run release-assets-macos --no-select
```

(Defined in root `pubspec.yaml` — builds both macOS triples, universal merge, zips, optional FFmpeg zips.)

```bash
dart run melos run release-assets-ios --no-select
```

(Zips **`platform-builds/ios`** triples into the same **`release-assets/<version>/`** folder — run **`ios-lib`** first if slices are missing.)

## CI matrix (optional)

- **macOS runner**: produce all mac zips (thin + universal + FFmpeg).  
- **Linux runner**: `collect-native -t x86_64-unknown-linux-gnu` (and arm if needed).  
- **Windows runner**: Windows triples.  

Upload all artifacts to the **same** GitHub release tag.

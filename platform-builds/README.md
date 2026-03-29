# `platform-builds/`

Prebuilt native artifacts for **`media_dart`** when the app sets:

```yaml
hooks:
  user_defines:
    media_dart:
      localBuild: false
```

## Layout

At the **repository root** (sibling of `media_dart/`):

```text
platform-builds/<os>/<rust-triple>/
```

Where `<os>` is one of `android`, `ios`, `linux`, `macos`, `windows`. There is **no** `release` / `debug` subdirectory: the library (and FFmpeg helpers on Linux/Windows) live **directly** under `<rust-triple>/`. Running `collect-native --debug` writes **debug** artifacts to the same paths (overwriting release files if present).

- **Library:** same filename as a normal hook build, e.g. `libmedia.so`, `libmedia.dylib`, or `media.dll` (see `mediaNativeLibraryFileName` / `mediaDynamicLibraryFileNameForRustTriple` in `tool/native_build/lib/media_rust_target.dart`).
- **Linux / Windows:** `ffmpeg` and `ffprobe` (or `.exe` on Windows) **in the same directory** as the library.
- **macOS:** `libmedia.dylib` only in this tree. **FFmpeg/ffprobe are embedded** in the dylib (`include_bytes!`); `collect-native` syncs them into `rust/media/bundled/current/` before `cargo` so the Dart macOS native-asset bundler is not given Mach-O **executables** as `CodeAsset`s (that breaks `dartdev` install-name handling).

Triples match the Rust targets used by the build hook (Android NDK, iOS device/simulator, desktop).

## Populating this directory

From the repo:

```bash
dart pub get
dart run melos run mac-lib --no-select   # or ios-lib / android-lib / linux-lib / windows-lib
```

Optional: from `tool/cli`, `dart run media_cli collect-native -t <triple>` (repeat `-t` or comma-separated), `--debug` to collect **debug** builds into the same per-triple folders.

**Android:** `collect-native` expects an NDK under `ANDROID_NDK_HOME`, `ANDROID_NDK_ROOT`, or `ANDROID_HOME`/`ANDROID_SDK_ROOT` + `ndk/<version>/`.

## Dylib size (macOS / desktop)

**macOS** prebuilts are a **single larger `libmedia.dylib`** (Rust/FRB plus embedded FFmpeg/ffprobe). **Linux/Windows** ship the library plus sidecar `ffmpeg` / `ffprobe` binaries in the same folder.

### Making builds smaller

1. **`[profile.release]`** in `media_dart/rust/media/Cargo.toml` (`strip`, `lto = "thin"`).

2. **Minimal FFmpeg** — swap in smaller ffmpeg/ffprobe builds (fewer codecs) via the same download paths in `media_ffmpeg_fetch.dart`.

3. **Optional** — `strip -x` on `libmedia.dylib` after `collect-native`.

Large binaries here are **gitignored** (see root `.gitignore`). Use CI artifacts or git-lfs if you need them in version control.

## FFmpeg licensing

Prebuilt FFmpeg binaries are **LGPL/GPL**-relevant. Confirm compliance before shipping.

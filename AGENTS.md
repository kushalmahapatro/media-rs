# AGENTS.md

## Cursor Cloud specific instructions

### Overview

This is a Flutter/Dart + Rust workspace for cross-platform media processing (`media-rs`). The main packages are:
- `media_dart` — Pure Dart + Rust (via flutter_rust_bridge); no Flutter SDK needed for tests
- `media_flutter` — Flutter plugin wrapping `media_dart` + Android Media3
- `media_flutter/example` — Flutter demo app (Linux desktop in Cloud)

### Key commands

| Task | Command | Working directory |
|------|---------|-------------------|
| Resolve deps | `dart pub get` | `/workspace` (root) |
| Lint (all) | `dart analyze .` | `/workspace` |
| Test (media_dart) | `dart test` | `/workspace/media_dart` |
| Test (Flutter) | `flutter test` | `/workspace/media_flutter/example` |
| Build Linux app | `flutter build linux --debug` | `/workspace/media_flutter/example` |
| Rust check | `cargo check --target x86_64-unknown-linux-gnu` | `/workspace/media_dart/rust/media` |

### Important caveats

- **Rust toolchain version**: The project uses Rust 1.93.0 (pinned in `media_dart/rust/media/rust-toolchain.toml`). The `dart test` / `flutter build` hooks invoke `rustup run 1.93.0 cargo build` automatically. Ensure `rustup install 1.93.0` has been run.
- **Native build hooks**: `dart test` in `media_dart` triggers Rust compilation via the build hook (`hook/build.dart`). The root `pubspec.yaml` sets `localBuild: true`, meaning Cargo builds the native library from source.
- **FFmpeg/ffprobe**: On Linux, the build hook downloads FFmpeg binaries automatically during `flutter build linux`. They appear in `build/.../bundle/lib/`.
- **Flutter Linux desktop deps**: Requires `clang`, `cmake`, `ninja-build`, `pkg-config`, `libgtk-3-dev`, `liblzma-dev`, `libstdc++-14-dev`. The `libstdc++.so` symlink may need to be created at `/usr/lib/x86_64-linux-gnu/libstdc++.so` pointing to the gcc version.
- **File picker in headless**: The `file_picker` plugin uses `zenity` or `kdialog` on Linux; these are not available in the headless Cloud VM. The app runs but the file picker won't open a dialog.
- **`flutter clean` before first build**: If you hit CMake permission errors during `flutter build linux`, run `flutter clean` first from the example directory.
- **PATH**: Flutter SDK is at `/opt/flutter/bin` — ensure it's on PATH.

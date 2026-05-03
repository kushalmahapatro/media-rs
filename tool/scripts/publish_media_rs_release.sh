#!/usr/bin/env bash
# Build native zips + FFmpeg zips, run tests, build Android release APK, optional Linux .deb,
# macOS installers (Darwin only), upload to GitHub release RELEASE_TAG (default v0.1.2 — must match
# media_dart/hook/build.dart).
#
# Hosts:
#   - Darwin: macOS + iOS native zips, Android (with NDK), macOS DMG/PKG, Android APK.
#   - Linux: Linux desktop native zips (see LINUX_NATIVE_TRIPLES), Android zips/APK, .deb.
#   - Windows (Git Bash / MSYS): Windows MSVC native zips (+ FFmpeg); Android steps are skipped
#     unless you set up NDK + Flutter for Windows.
#
# Windows MSVC libraries are not cross-built from Linux (Flutter expects *-pc-windows-msvc); use a
# Windows host or `melos run release-assets-windows` / the same collect-native invocation there.
#
# Prerequisites (typical macOS release): Xcode, CocoaPods, Android NDK (ANDROID_NDK_HOME), Rust
# targets, gh auth, create-dmg (brew) for DMG jobs, Flutter on PATH (or FLUTTER_TOOL=fvm\ flutter).
# Linux desktop: rustup target add …; set LINUX_NATIVE_TRIPLES to both GNU triples if you have cross gcc.
# Linux .deb: sudo apt install clang cmake ninja-build pkg-config libgtk-3-dev liblzma-dev
#
# Usage (from repo root):
#   ./tool/scripts/publish_media_rs_release.sh
#   SKIP_NATIVE=1 SKIP_TESTS=1 ./tool/scripts/publish_media_rs_release.sh
#   SKIP_ANDROID_NATIVE=1 SKIP_IOS_NATIVE=1
#   SKIP_LINUX_NATIVE=1 SKIP_LINUX_DEB=1
#   LINUX_NATIVE_TRIPLES="aarch64-unknown-linux-gnu x86_64-unknown-linux-gnu"   # override Linux triples
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$REPO_ROOT"

RELEASE_TAG="${RELEASE_TAG:-v0.1.2}"
SKIP_NATIVE="${SKIP_NATIVE:-0}"
SKIP_TESTS="${SKIP_TESTS:-0}"
SKIP_GH="${SKIP_GH:-0}"
SKIP_ANDROID_NATIVE="${SKIP_ANDROID_NATIVE:-0}"
SKIP_IOS_NATIVE="${SKIP_IOS_NATIVE:-0}"
SKIP_ANDROID_APK="${SKIP_ANDROID_APK:-0}"
SKIP_LINUX_NATIVE="${SKIP_LINUX_NATIVE:-0}"
SKIP_WINDOWS_NATIVE="${SKIP_WINDOWS_NATIVE:-0}"
SKIP_LINUX_DEB="${SKIP_LINUX_DEB:-0}"

if command -v fvm >/dev/null 2>&1; then
  export FLUTTER_TOOL="${FLUTTER_TOOL:-fvm flutter}"
else
  export FLUTTER_TOOL="${FLUTTER_TOOL:-flutter}"
fi

EXAMPLE="$REPO_ROOT/media_flutter/example"
APP_VER="$(grep -E '^version:' "$EXAMPLE/pubspec.yaml" | head -1 | awk '{print $2}' | tr -d \" | cut -d+ -f1)"

HOST="$(uname -s)"

echo "==> Repo: $REPO_ROOT"
echo "==> Host: $HOST"
echo "==> Release tag: $RELEASE_TAG (hook + GitHub assets)"
echo "==> App version: $APP_VER"
echo "==> Flutter: $FLUTTER_TOOL"

dart pub get

if [[ "$SKIP_NATIVE" != "1" ]]; then
  if [[ "$HOST" == Darwin ]]; then
    echo "=== collect-native (macOS thin + universal + FFmpeg zips) ==="
    (cd "$REPO_ROOT/tool/cli" && dart run media_cli collect-native \
      --package-root ../../media_dart \
      -t aarch64-apple-darwin \
      -t x86_64-apple-darwin \
      --archive-format zip \
      --archive-version "$RELEASE_TAG" \
      --macos-universal \
      --archive-ffmpeg zip)

    if [[ "$SKIP_IOS_NATIVE" != "1" ]]; then
      echo "=== collect-native (iOS device + simulator: build + zip) ==="
      (cd "$REPO_ROOT/tool/cli" && dart run media_cli collect-native \
        --package-root ../../media_dart \
        -t aarch64-apple-ios \
        -t aarch64-apple-ios-sim \
        -t x86_64-apple-ios \
        --archive-format zip \
        --archive-version "$RELEASE_TAG")
    else
      echo "=== skip iOS native (SKIP_IOS_NATIVE=1) ==="
    fi
  else
    echo "=== skip macOS / iOS native (requires Darwin + Xcode) ==="
  fi

  if [[ "$SKIP_ANDROID_NATIVE" != "1" ]] && { [[ "$HOST" == Darwin ]] || [[ "$HOST" == Linux ]]; }; then
    echo "=== collect-native (Android ABIs: build + zip) ==="
    (cd "$REPO_ROOT/tool/cli" && dart run media_cli collect-native \
      --package-root ../../media_dart \
      -t aarch64-linux-android \
      -t x86_64-linux-android \
      -t armv7-linux-androideabi \
      --archive-format zip \
      --archive-version "$RELEASE_TAG")
  elif [[ "$SKIP_ANDROID_NATIVE" != "1" ]]; then
    echo "=== skip Android native on host $HOST (use Darwin or Linux + NDK) ==="
  else
    echo "=== skip Android native (SKIP_ANDROID_NATIVE=1) ==="
  fi

  if [[ "$HOST" == Linux ]] && [[ "$SKIP_LINUX_NATIVE" != "1" ]]; then
    if [[ -z "${LINUX_NATIVE_TRIPLES:-}" ]]; then
      case "$(uname -m)" in
        x86_64) LINUX_NATIVE_TRIPLES="x86_64-unknown-linux-gnu" ;;
        aarch64) LINUX_NATIVE_TRIPLES="aarch64-unknown-linux-gnu" ;;
        *) LINUX_NATIVE_TRIPLES="" ;;
      esac
    fi
    if [[ -n "$LINUX_NATIVE_TRIPLES" ]]; then
      echo "=== collect-native (Linux desktop: $LINUX_NATIVE_TRIPLES) ==="
      args=(collect-native --package-root ../../media_dart)
      for t in $LINUX_NATIVE_TRIPLES; do
        args+=(-t "$t")
      done
      args+=(--archive-format zip --archive-version "$RELEASE_TAG" --archive-ffmpeg zip)
      (cd "$REPO_ROOT/tool/cli" && dart run media_cli "${args[@]}")
    else
      echo "=== skip Linux native (unknown uname -m; set LINUX_NATIVE_TRIPLES) ==="
    fi
  elif [[ "$HOST" == Linux ]]; then
    echo "=== skip Linux native (SKIP_LINUX_NATIVE=1) ==="
  fi

  case "$HOST" in
    MINGW* | MSYS* | CYGWIN*)
      if [[ "$SKIP_WINDOWS_NATIVE" != "1" ]]; then
        echo "=== collect-native (Windows MSVC: build + zip) ==="
        (cd "$REPO_ROOT/tool/cli" && dart run media_cli collect-native \
          --package-root ../../media_dart \
          -t aarch64-pc-windows-msvc \
          -t x86_64-pc-windows-msvc \
          --archive-format zip \
          --archive-version "$RELEASE_TAG" \
          --archive-ffmpeg zip)
      else
        echo "=== skip Windows native (SKIP_WINDOWS_NATIVE=1) ==="
      fi
      ;;
  esac
else
  echo "=== skip all native collect (SKIP_NATIVE=1) ==="
fi

ASSET_DIR="$REPO_ROOT/release-assets/$RELEASE_TAG"
if [[ ! -d "$ASSET_DIR" ]]; then
  echo "Missing $ASSET_DIR — run without SKIP_NATIVE first (or populate release-assets manually)." >&2
  exit 1
fi

if [[ "$SKIP_GH" != "1" ]]; then
  echo "=== GitHub release + upload native/FFmpeg zips ==="
  if ! gh release view "$RELEASE_TAG" >/dev/null 2>&1; then
    gh release create "$RELEASE_TAG" \
      --title "$RELEASE_TAG" \
      --notes "media-rs native libraries + FFmpeg ([RELEASE_ASSETS.md](https://github.com/kushalmahapatro/media-rs/blob/main/RELEASE_ASSETS.md))."
  fi
  shopt -s nullglob
  assets=( "$ASSET_DIR"/* )
  shopt -u nullglob
  if [[ ${#assets[@]} -eq 0 ]]; then
    echo "No files under $ASSET_DIR to upload." >&2
    exit 1
  fi
  gh release upload "$RELEASE_TAG" "$ASSET_DIR"/* --clobber
else
  echo "=== skip gh upload (SKIP_GH=1) ==="
fi

if [[ "$SKIP_TESTS" != "1" ]]; then
  echo "=== dart test (media_dart) ==="
  (cd "$REPO_ROOT/media_dart" && dart test)
  echo "=== flutter test (example) ==="
  (cd "$EXAMPLE" && $FLUTTER_TOOL test)
else
  echo "=== skip tests (SKIP_TESTS=1) ==="
fi

write_arch() {
  local mode="$1"
  local pod_arch="${2:-}"
  bash "$REPO_ROOT/tool/scripts/write_macos_arch_override.sh" "$mode"
  if [[ -n "$pod_arch" ]]; then
    export MEDIA_MACOS_SINGLE_ARCH="$pod_arch"
  else
    unset MEDIA_MACOS_SINGLE_ARCH || true
  fi
  (cd "$EXAMPLE/macos" && pod install)
}

build_macos_variant() {
  local label="$1"
  local pod_arch="${2:-}"
  echo "=== macOS build: $label ==="
  write_arch "$label" "$pod_arch"
  (cd "$EXAMPLE" && $FLUTTER_TOOL clean)
  (cd "$EXAMPLE" && $FLUTTER_TOOL build macos --release)
}

package_installers() {
  local suffix="$1"
  local dist="$REPO_ROOT/dist/$APP_VER"
  mkdir -p "$dist"
  echo "=== DMG ($suffix) ==="
  (cd "$EXAMPLE" && dart run media_cli dist --jobs macos-dmg --skip-clean)
  shopt -s nullglob
  local dmgs=( "$dist"/*.dmg )
  shopt -u nullglob
  if [[ ${#dmgs[@]} -eq 0 ]]; then
    echo "No .dmg found under $dist" >&2
    exit 1
  fi
  local latest
  latest="$(ls -t "${dmgs[@]}" | head -1)"
  mv -f "$latest" "$dist/media-$APP_VER-macos-$suffix.dmg"

  echo "=== PKG ($suffix) ==="
  (cd "$EXAMPLE" && dart run media_cli package-macos-pkg --no-build \
    --output "$dist/media-$APP_VER-macos-$suffix.pkg")
}

if [[ "$SKIP_ANDROID_APK" != "1" ]] && { [[ "$HOST" == Darwin ]] || [[ "$HOST" == Linux ]]; }; then
  echo "=== Android release APK (Fastforge; hook should resolve prebuilts from $RELEASE_TAG) ==="
  (cd "$EXAMPLE" && $FLUTTER_TOOL pub get)
  (cd "$EXAMPLE" && $FLUTTER_TOOL clean)
  (cd "$EXAMPLE" && dart run media_cli dist --jobs android-apk --skip-clean)
elif [[ "$SKIP_ANDROID_APK" != "1" ]]; then
  echo "=== skip Android APK on host $HOST ==="
else
  echo "=== skip Android APK (SKIP_ANDROID_APK=1) ==="
fi

if [[ "$HOST" == Linux ]] && [[ "$SKIP_LINUX_DEB" != "1" ]]; then
  echo "=== Linux .deb (Fastforge; linux/packaging/deb/make_config.yaml) ==="
  (cd "$EXAMPLE" && $FLUTTER_TOOL pub get)
  (cd "$EXAMPLE" && $FLUTTER_TOOL clean)
  (cd "$EXAMPLE" && dart run media_cli dist --jobs linux-deb --skip-clean)
elif [[ "$HOST" == Linux ]]; then
  echo "=== skip Linux .deb (SKIP_LINUX_DEB=1) ==="
fi

if [[ "$HOST" == Darwin ]]; then
  echo "=== macOS .app builds + installers (3 variants) ==="
  export PATH="$REPO_ROOT/tool/shims:/opt/homebrew/bin:/usr/local/bin:$PATH"

  build_macos_variant universal ""
  package_installers universal

  build_macos_variant arm64 arm64
  package_installers arm64

  build_macos_variant x86_64 x86_64
  package_installers x86_64

  write_arch universal ""
  unset MEDIA_MACOS_SINGLE_ARCH || true
  (cd "$EXAMPLE/macos" && pod install)
else
  echo "=== skip macOS DMG/PKG (Darwin host only) ==="
fi

echo "=== Upload installers (DMG/PKG/APK/.deb when present) ==="
DIST="$REPO_ROOT/dist/$APP_VER"
if [[ "$SKIP_GH" != "1" ]]; then
  uploads=()
  for f in \
    "$DIST/media-$APP_VER-macos-universal.dmg" \
    "$DIST/media-$APP_VER-macos-universal.pkg" \
    "$DIST/media-$APP_VER-macos-arm64.dmg" \
    "$DIST/media-$APP_VER-macos-arm64.pkg" \
    "$DIST/media-$APP_VER-macos-x86_64.dmg" \
    "$DIST/media-$APP_VER-macos-x86_64.pkg"; do
    [[ -f "$f" ]] && uploads+=("$f")
  done
  shopt -s nullglob
  for apk in "$DIST"/*.apk; do
    [[ -f "$apk" ]] && uploads+=("$apk")
  done
  for deb in "$DIST"/*.deb; do
    [[ -f "$deb" ]] && uploads+=("$deb")
  done
  shopt -u nullglob
  if [[ ${#uploads[@]} -gt 0 ]]; then
    gh release upload "$RELEASE_TAG" "${uploads[@]}" --clobber
  fi
else
  echo "Skipping installer upload (SKIP_GH=1). Artifacts under $DIST/"
fi

echo "Done. Installers / APK / DEB: $DIST/"
echo "Native zips: $ASSET_DIR/"

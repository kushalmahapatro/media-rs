#!/usr/bin/env bash
# Build native zips + FFmpeg zips, run tests, build Android release APK, macOS installers
# (universal + arm64 + x86_64), upload to GitHub release RELEASE_TAG (default v0.1.2 — must match
# media_dart/hook/build.dart).
#
# Prerequisites: Xcode, CocoaPods, Android NDK (ANDROID_NDK_HOME), Rust targets (e.g.
# darwin + iOS + Android: rustup target add aarch64-apple-darwin x86_64-apple-darwin
# aarch64-apple-ios aarch64-apple-ios-sim x86_64-apple-ios aarch64-linux-android
# x86_64-linux-android armv7-linux-androideabi),
# gh auth login, create-dmg (brew) for DMG jobs, Flutter on PATH (or set FLUTTER_TOOL=fvm\ flutter).
#
# Usage (from repo root):
#   chmod +x tool/scripts/publish_media_rs_release.sh
#   ./tool/scripts/publish_media_rs_release.sh
#   SKIP_NATIVE=1 SKIP_TESTS=1 ./tool/scripts/publish_media_rs_release.sh   # installers only
#   SKIP_ANDROID_NATIVE=1   # skip Android .so zips (no NDK)
#   SKIP_IOS_NATIVE=1       # skip iOS zips (use after `melos run ios-lib` + archive-only, or no Xcode)
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

if command -v fvm >/dev/null 2>&1; then
  export FLUTTER_TOOL="${FLUTTER_TOOL:-fvm flutter}"
else
  export FLUTTER_TOOL="${FLUTTER_TOOL:-flutter}"
fi

EXAMPLE="$REPO_ROOT/media_flutter/example"
APP_VER="$(grep -E '^version:' "$EXAMPLE/pubspec.yaml" | head -1 | awk '{print $2}' | tr -d \" | cut -d+ -f1)"

echo "==> Repo: $REPO_ROOT"
echo "==> Release tag: $RELEASE_TAG (hook + GitHub assets)"
echo "==> App version: $APP_VER"
echo "==> Flutter: $FLUTTER_TOOL"

dart pub get

if [[ "$SKIP_NATIVE" != "1" ]]; then
  echo "=== [1/8] collect-native (macOS thin + universal + FFmpeg zips) ==="
  (cd "$REPO_ROOT/tool/cli" && dart run media_cli collect-native \
    --package-root ../../media_dart \
    -t aarch64-apple-darwin \
    -t x86_64-apple-darwin \
    --archive-format zip \
    --archive-version "$RELEASE_TAG" \
    --macos-universal \
    --archive-ffmpeg zip)

  if [[ "$SKIP_IOS_NATIVE" != "1" ]]; then
    echo "=== [2/8] collect-native (iOS device + simulator: build + zip) ==="
    (cd "$REPO_ROOT/tool/cli" && dart run media_cli collect-native \
      --package-root ../../media_dart \
      -t aarch64-apple-ios \
      -t aarch64-apple-ios-sim \
      -t x86_64-apple-ios \
      --archive-format zip \
      --archive-version "$RELEASE_TAG")
  else
    echo "=== [2/8] skip iOS native (SKIP_IOS_NATIVE=1) ==="
  fi

  if [[ "$SKIP_ANDROID_NATIVE" != "1" ]]; then
    echo "=== [3/8] collect-native (Android ABIs: build + zip) ==="
    (cd "$REPO_ROOT/tool/cli" && dart run media_cli collect-native \
      --package-root ../../media_dart \
      -t aarch64-linux-android \
      -t x86_64-linux-android \
      -t armv7-linux-androideabi \
      --archive-format zip \
      --archive-version "$RELEASE_TAG")
  else
    echo "=== [3/8] skip Android native (SKIP_ANDROID_NATIVE=1) ==="
  fi
else
  echo "=== [1-3/8] skip native (SKIP_NATIVE=1) ==="
fi

ASSET_DIR="$REPO_ROOT/release-assets/$RELEASE_TAG"
if [[ ! -d "$ASSET_DIR" ]]; then
  echo "Missing $ASSET_DIR — run without SKIP_NATIVE first." >&2
  exit 1
fi

if [[ "$SKIP_GH" != "1" ]]; then
  echo "=== [4/8] GitHub release + upload native/FFmpeg zips ==="
  if ! gh release view "$RELEASE_TAG" >/dev/null 2>&1; then
    gh release create "$RELEASE_TAG" \
      --title "$RELEASE_TAG" \
      --notes "media-rs native libraries + FFmpeg ([RELEASE_ASSETS.md](https://github.com/kushalmahapatro/media-rs/blob/main/RELEASE_ASSETS.md))."
  fi
  gh release upload "$RELEASE_TAG" "$ASSET_DIR"/* --clobber
else
  echo "=== [4/8] skip gh upload (SKIP_GH=1) ==="
fi

if [[ "$SKIP_TESTS" != "1" ]]; then
  echo "=== [5/8] dart test (media_dart) ==="
  (cd "$REPO_ROOT/media_dart" && dart test)
  echo "=== [6/8] flutter test (example) ==="
  (cd "$EXAMPLE" && $FLUTTER_TOOL test)
else
  echo "=== [5-6/8] skip tests (SKIP_TESTS=1) ==="
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
  # Fastforge writes under dist/<version>/ — take newest .dmg if name varies.
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

if [[ "$SKIP_ANDROID_APK" != "1" ]]; then
  echo "=== [7/8] Android release APK (Fastforge; hook should resolve prebuilts from $RELEASE_TAG) ==="
  (cd "$EXAMPLE" && $FLUTTER_TOOL pub get)
  (cd "$EXAMPLE" && $FLUTTER_TOOL clean)
  (cd "$EXAMPLE" && dart run media_cli dist --jobs android-apk --skip-clean)
else
  echo "=== [7/8] skip Android APK (SKIP_ANDROID_APK=1) ==="
fi

echo "=== [8/8] macOS .app builds + installers (3 variants) ==="
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

echo "=== Upload macOS DMG/PKG + Android APK ==="
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
  shopt -u nullglob
  if [[ ${#uploads[@]} -gt 0 ]]; then
    gh release upload "$RELEASE_TAG" "${uploads[@]}" --clobber
  fi
else
  echo "Skipping DMG/PKG/APK upload (SKIP_GH=1). Artifacts under $DIST/"
fi

echo "Done. Installers and APK: $DIST/"
echo "Native zips: $ASSET_DIR/"

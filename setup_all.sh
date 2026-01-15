#!/bin/bash
set -euo pipefail

# One-stop dependency builder for this repo (entrypoint).
# This file lives at repo root. Supporting scripts live under scripts/support/.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$SCRIPT_DIR"

usage() {
  cat <<'EOF'
Usage:
  ./setup_all.sh [--all] [--macos] [--ios] [--android] [--linux] [--skip-openh264]

Defaults:
  - On macOS: builds macos + ios + android
  - On Linux: builds linux + android

Env:
  - ANDROID_NDK_HOME: required for --android
EOF
}

want_all=false
want_macos=false
want_ios=false
want_android=false
want_linux=false
skip_openh264=false

for arg in "$@"; do
  case "$arg" in
    --all) want_all=true ;;
    --macos) want_macos=true ;;
    --ios) want_ios=true ;;
    --android) want_android=true ;;
    --linux) want_linux=true ;;
    --skip-openh264) skip_openh264=true ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown arg: $arg"; usage; exit 2 ;;
  esac
done

host_os="$(uname -s | tr '[:upper:]' '[:lower:]')"

if $want_all; then
  want_macos=true
  want_ios=true
  want_android=true
  want_linux=true
fi

# Sensible defaults
if ! $want_macos && ! $want_ios && ! $want_android && ! $want_linux; then
  if [[ "$host_os" == "darwin" ]]; then
    want_macos=true
    want_ios=true
    want_android=true
  elif [[ "$host_os" == "linux" ]]; then
    want_linux=true
    want_android=true
  else
    echo "Unsupported host OS for bash setup: $host_os"
    echo "On Windows, use: setup_all.bat"
    exit 2
  fi
fi

cd "$PROJECT_ROOT"

SUPPORT_DIR="$PROJECT_ROOT/scripts/support"
if [ ! -d "$SUPPORT_DIR" ]; then
  echo "ERROR: support scripts directory not found: $SUPPORT_DIR"
  exit 2
fi

echo "Repo: $PROJECT_ROOT"
echo "Host: $host_os"
echo "Targets: macos=$want_macos ios=$want_ios android=$want_android linux=$want_linux"

if $want_macos; then
  if [[ "$host_os" != "darwin" ]]; then
    echo "Skipping macOS deps: host is not macOS."
  else
    echo "=== macOS: libheif (universal) ==="
    "$SUPPORT_DIR/setup_libheif_all.sh" --macos-only
    echo "=== macOS: ffmpeg (universal) ==="
    if $skip_openh264; then
      "$SUPPORT_DIR/setup_ffmpeg.sh" --skip-openh264
    else
      "$SUPPORT_DIR/setup_ffmpeg.sh"
    fi
  fi
fi

if $want_ios; then
  if [[ "$host_os" != "darwin" ]]; then
    echo "Skipping iOS deps: host is not macOS."
  else
    echo "=== iOS: libheif ==="
    "$SUPPORT_DIR/setup_libheif_all.sh" --ios-only
    echo "=== iOS: ffmpeg ==="
    if $skip_openh264; then
      "$SUPPORT_DIR/setup_ffmpeg_ios.sh" --skip-openh264
    else
      "$SUPPORT_DIR/setup_ffmpeg_ios.sh"
    fi
  fi
fi

if $want_android; then
  if [[ -z "${ANDROID_NDK_HOME:-}" ]]; then
    echo "ERROR: ANDROID_NDK_HOME is required for Android builds."
    exit 2
  fi
  echo "=== Android: libheif ==="
  "$SUPPORT_DIR/setup_libheif_all.sh" --android-only
  echo "=== Android: ffmpeg (+openh264) ==="
  if $skip_openh264; then
    "$SUPPORT_DIR/setup_ffmpeg_android.sh" --skip-openh264
  else
    "$SUPPORT_DIR/setup_ffmpeg_android.sh"
  fi
fi

if $want_linux; then
  if [[ "$host_os" != "linux" ]]; then
    echo "Skipping Linux deps: host is not Linux."
  else
    echo "=== Linux: openh264 ==="
    "$SUPPORT_DIR/setup_openh264_linux.sh"
    echo "=== Linux: libheif ==="
    "$SUPPORT_DIR/setup_libheif_linux.sh"
    echo "=== Linux: ffmpeg (+openh264) ==="
    "$SUPPORT_DIR/setup_ffmpeg_linux.sh"
  fi
fi

echo "Done. third_party installs are ready."



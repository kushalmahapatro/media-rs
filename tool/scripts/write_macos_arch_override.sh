#!/usr/bin/env bash
# Writes or removes Runner/Configs/ArchOverride.xcconfig for single-arch macOS builds.
# Usage: write_macos_arch_override.sh universal|arm64|x86_64
set -euo pipefail
MODE="${1:-universal}"
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
CFG="$ROOT/media_flutter/example/macos/Runner/Configs/ArchOverride.xcconfig"

case "$MODE" in
  universal)
    rm -f "$CFG"
    echo "Removed $CFG (universal binary)"
    ;;
  arm64)
    mkdir -p "$(dirname "$CFG")"
    printf '%s\n' 'EXCLUDED_ARCHS[sdk=macosx*] = x86_64' >"$CFG"
    echo "Wrote $CFG (Apple Silicon only)"
    ;;
  x86_64)
    mkdir -p "$(dirname "$CFG")"
    printf '%s\n' 'EXCLUDED_ARCHS[sdk=macosx*] = arm64' >"$CFG"
    echo "Wrote $CFG (Intel only)"
    ;;
  *)
    echo "usage: $0 universal|arm64|x86_64" >&2
    exit 64
    ;;
esac

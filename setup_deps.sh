#!/bin/bash
set -euo pipefail

# Backwards-compatible alias for the main entrypoint at repo root.
exec "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/setup_all.sh" "$@"



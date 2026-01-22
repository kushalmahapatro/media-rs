#!/bin/bash
# Wrapper script that automatically sources setup_env.sh before running cargo
# Usage: ./cargo-wrapper.sh check, ./cargo-wrapper.sh build, etc.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/setup_env.sh" > /dev/null 2>&1
exec cargo "$@"


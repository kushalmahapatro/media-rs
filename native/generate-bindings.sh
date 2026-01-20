#!/bin/bash
# Generate Flutter Rust Bridge bindings with proper environment setup
# Usage: ./generate-bindings.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/setup_env.sh" > /dev/null 2>&1
flutter_rust_bridge_codegen generate





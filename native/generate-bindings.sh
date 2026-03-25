#!/bin/bash
# Generate Flutter Rust Bridge bindings with proper environment setup
# Usage: from repo root: ./native/generate-bindings.sh
#        or: cd native && ./generate-bindings.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/setup_env.sh" > /dev/null 2>&1

# Codegen loads flutter_rust_bridge.yaml from cwd unless --config-file is set; paths in the
# yaml (rust_root, dart_output) are relative to the native/ crate.
cd "$SCRIPT_DIR" || exit 1
exec flutter_rust_bridge_codegen generate --config-file "$SCRIPT_DIR/flutter_rust_bridge.yaml"





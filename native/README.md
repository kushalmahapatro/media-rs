# Media Native (Rust)

This directory contains the Rust native code for the media plugin.

## Building

Before running `cargo check`, `cargo build`, or `cargo test`, you need to set up the environment variables to point to the pre-built FFmpeg and libheif libraries.

### Quick Setup

**Option 1: Use the wrapper script (Recommended)**

```bash
# In the native/ directory
./cargo-wrapper.sh check
./cargo-wrapper.sh build
./cargo-wrapper.sh test
```

**Option 2: Source the setup script manually**

**Important:** You must use `source` (not `sh`) to run the setup script, otherwise environment variables won't persist:

```bash
# In the native/ directory
source setup_env.sh
cargo check
cargo build
cargo test
```

Or run it in one line:

```bash
source setup_env.sh && cargo check
```

**⚠️ Common Mistake:** Don't run `sh setup_env.sh` - this runs the script in a subshell and environment variables won't persist. Always use `source setup_env.sh` instead.

**Note:** The `source` command must be run in the same shell session where you run cargo. If you open a new terminal, you'll need to source the script again.

### Manual Setup

If you prefer to set the environment variables manually:

```bash
export FFMPEG_DIR="$(pwd)/../third_party/ffmpeg_install"
export LIBHEIF_DIR="$(pwd)/../third_party/libheif_install/macos/universal"
export PKG_CONFIG_PATH="$(pwd)/../third_party/libheif_install/macos/universal/lib/pkgconfig:$(pwd)/../third_party/ffmpeg_install/lib/pkgconfig"
export PKG_CONFIG_ALLOW_SYSTEM_LIBS=1
export PKG_CONFIG_ALLOW_SYSTEM_CFLAGS=1
```

## Generating Flutter Bindings

After adding or modifying Rust functions that should be exposed to Flutter, regenerate the bindings:

```bash
# In the native/ directory
./generate-bindings.sh
```

Or manually:
```bash
source setup_env.sh && flutter_rust_bridge_codegen generate
```

**Note:** The environment variables must be set for codegen to work, as it runs `cargo expand` which needs access to FFmpeg and libheif libraries.

## Environment Variables

- `FFMPEG_DIR`: Path to the FFmpeg installation directory
- `LIBHEIF_DIR`: Path to the libheif installation directory  
- `PKG_CONFIG_PATH`: Colon-separated list of pkg-config directories
- `PKG_CONFIG_ALLOW_SYSTEM_LIBS`: Allow system libraries (set to 1)
- `PKG_CONFIG_ALLOW_SYSTEM_CFLAGS`: Allow system CFLAGS (set to 1)


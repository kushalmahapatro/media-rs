#!/usr/bin/env python3
"""Fix mediacodec crate for Windows cross-compilation."""
import json, subprocess, sys

def ssh(cmd):
    result = subprocess.run(f"ssh windows 'cmd /c \"{cmd}\"'", shell=True, capture_output=True, text=True, timeout=60)
    print(result.stdout.strip())
    if result.returncode != 0 and result.stderr:
        print(f"STDERR: {result.stderr.strip()}", file=sys.stderr)
    return result

def ssh_file_write(path, content):
    """Write a file on Windows via ssh."""
    encoded = json.dumps(content)
    cmd = f'python -c "import json,sys;open(sys.argv[1],\'w\').write(json.loads(sys.argv[2]))" "{path}" "{encoded}"'
    result = subprocess.run(f"ssh windows 'cmd /c \"{cmd}\"'", shell=True, capture_output=True, text=True, timeout=60)
    print(f"WRITE {path}: rc={result.returncode}")
    if result.returncode != 0:
        print(f"STDERR: {result.stderr.strip()}", file=sys.stderr)
    return result

# Step 1: Fix mediacodec/Cargo.toml - add [target.'cfg(not(target_os = "android"))'.dependencies] to make it compile on non-Android
# The key issue: mediacodec uses `link(name = "mediandk")` which requires Android NDK
# Solution: make the whole crate conditionally compile only on Android

mediacodec_cargo = '''//! This crate provides bindings to the MediaCodec APIs in the Android NDK.
//!
//! On non-Android platforms, this crate compiles to a no-op to allow
//! the parent `media` crate to build cross-platform.

#![cfg(target_os = "android")]

mod codec;
mod crypto;
mod error;
mod extractor;
mod format;
mod muxer;
mod native_window;
mod samples;

pub use codec::*;
pub use crypto::*;
pub use error::*;
pub use extractor::*;
pub use format::*;
pub use muxer::*;
pub use native_window::*;
pub use samples::*;
'''

ssh_file_write(r'C:\Users\kusha\Documents\Projects\media-rs\media_dart\rust\mediacodec\src\lib.rs', mediacodec_cargo)

# Step 2: Fix media/Cargo.toml - remove path dependency on mediacodec for non-Android
# We need to change the Cargo.toml to not use path dependency for non-android
# Actually, looking at the Cargo.toml, it already uses cfg(target_os = "android") for the mediacodec dependency
# So the Cargo.toml is correct. The issue is in mediacodec itself.
# The cfg(target_os = "android") on the whole crate module is the fix.

print("Done with mediacodec fix")

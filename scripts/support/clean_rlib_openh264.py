#!/usr/bin/env python3
"""Remove incompatible object files from .rlib archives to fix architecture mismatches."""
import sys
import os
import subprocess
import tempfile
import shutil
from pathlib import Path

def clean_rlib(rlib_path):
    """Remove incompatible object files from an .rlib archive by deleting it to force rebuild."""
    rlib_path = Path(rlib_path).resolve()  # Use absolute path
    if not rlib_path.exists():
        print(f"Error: {rlib_path} does not exist")
        return False
    
    # Try to find llvm-ar from Android NDK (more reliable for cross-platform archives)
    ar_tool = 'ar'
    android_ndk_home = os.environ.get('ANDROID_NDK_HOME') or os.environ.get('ANDROID_NDK_ROOT')
    if android_ndk_home:
        # Try darwin-x86_64 first (common on Apple Silicon via Rosetta)
        llvm_ar = Path(android_ndk_home) / 'toolchains' / 'llvm' / 'prebuilt' / 'darwin-x86_64' / 'bin' / 'llvm-ar'
        if not llvm_ar.exists():
            # Try darwin-arm64 as fallback
            llvm_ar = Path(android_ndk_home) / 'toolchains' / 'llvm' / 'prebuilt' / 'darwin-arm64' / 'bin' / 'llvm-ar'
        if llvm_ar.exists():
            ar_tool = str(llvm_ar.resolve())
            print(f"Using llvm-ar from NDK: {ar_tool}")
    
    # List contents to check for incompatible files
    result = subprocess.run([ar_tool, 't', str(rlib_path)], capture_output=True, text=True, cwd=str(rlib_path.parent))
    if result.returncode != 0:
        print(f"Error: Failed to list contents of {rlib_path}: {result.stderr}")
        # If we can't list, assume it's corrupted and delete it
        print(f"Deleting corrupted .rlib file: {rlib_path}")
        rlib_path.unlink()
        return True
    
    files = result.stdout.strip().split('\n')
    # Filter out empty lines and handle trailing slashes
    files = [f.strip().rstrip('/') for f in files if f.strip()]
    
    # Check for any .o files (FFmpeg object files that might be incompatible)
    # These should not be in the .rlib - they should only be linked at final binary stage
    # Rust should not embed object files from static libraries into .rlib files
    o_files = [f for f in files if f.endswith('.o')]
    
    if not o_files:
        print(f"No .o files found in {rlib_path} - archive is clean")
        return True
    
    print(f"Found {len(o_files)} .o file(s) in {rlib_path}: {o_files[:5]}...")
    print(f"These object files should not be embedded in .rlib - deleting .rlib to force rebuild")
    
    # Delete the .rlib file to force Cargo to rebuild it from scratch
    # This ensures no incompatible object files are embedded
    try:
        rlib_path.unlink()
        print(f"Successfully deleted {rlib_path} - Cargo will rebuild it")
        
        # Also delete the fingerprint file to force a complete rebuild
        fingerprint_dir = rlib_path.parent.parent / '.fingerprint'
        if fingerprint_dir.exists():
            # Find fingerprint files for this crate
            for fingerprint_file in fingerprint_dir.glob('ffmpeg-sys-next-*'):
                print(f"Deleting fingerprint file: {fingerprint_file}")
                fingerprint_file.unlink()
        
        return True
    except Exception as e:
        print(f"Error: Failed to delete {rlib_path}: {e}")
        return False

if __name__ == '__main__':
    if len(sys.argv) < 2:
        print("Usage: clean_rlib_openh264.py <path_to.rlib>")
        sys.exit(1)
    
    rlib_path = sys.argv[1]
    success = clean_rlib(rlib_path)
    sys.exit(0 if success else 1)


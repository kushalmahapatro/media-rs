# Quick Fix: LIBHEIF_DIR Not Set

## Problem
When running `cargo test`, you're getting this error:
```
Could not find library in Vcpkg tree package libheif is not installed
```

## Solution

### Option 1: Quick Fix (Set Environment Variables)

**In your current terminal/PowerShell, run:**

```cmd
cd D:\media-rs\media-rs
call native\setup_env.bat
```

This will set the environment variables for your current session.

**Then run your tests:**
```cmd
cd native
cargo test --lib test_concurrent_operations -- --nocapture
```

### Option 2: Build Libraries First (If Not Built)

If libheif hasn't been built yet:

```cmd
cd D:\media-rs\media-rs
dart run tool/setup.dart --windows
```

This will:
1. Build FFmpeg
2. Build libheif
3. Build OpenH264

**Then set environment and run tests:**
```cmd
call native\setup_env.bat
cd native
cargo test --lib test_concurrent_operations -- --nocapture
```

### Option 3: Use the Setup and Test Script

I've created a script that does everything:

```cmd
cd D:\media-rs\media-rs
tool\setup_and_test.bat D:\media-rs\media-rs\native\HDR.MOV
```

This will:
1. Set environment variables
2. Build libraries if needed
3. Run all tests

## Permanent Fix (Optional)

To set environment variables permanently (for all future sessions):

```cmd
cd D:\media-rs\media-rs
call native\setup_env.bat
setx FFMPEG_DIR "%FFMPEG_DIR%"
setx LIBHEIF_DIR "%LIBHEIF_DIR%"
setx PKG_CONFIG_PATH "%PKG_CONFIG_PATH%"
```

**Note:** You'll need to restart your terminal after using `setx`.

## Verify Environment Variables

To check if they're set:

```cmd
echo %LIBHEIF_DIR%
echo %FFMPEG_DIR%
echo %PKG_CONFIG_PATH%
```

They should point to:
- `LIBHEIF_DIR`: `D:\media-rs\media-rs\third_party\generated\libheif_install\windows\x86_64`
- `FFMPEG_DIR`: `D:\media-rs\media-rs\third_party\generated\ffmpeg_install\windows\x86_64`

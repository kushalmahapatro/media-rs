@echo off
REM Setup environment and run tests
REM Usage: tool\setup_and_test.bat [test_video_path]

setlocal
set "SCRIPT_DIR=%~dp0"
set "PROJECT_ROOT=%SCRIPT_DIR%.."
set "TEST_VIDEO=%~1"

echo === Setting up environment and running tests ===
echo.

REM 1. Setup environment variables
echo Step 1: Setting up environment variables...
call "%PROJECT_ROOT%\native\setup_env.bat"

REM 2. Build libraries if needed
echo.
echo Step 2: Building libraries (if needed)...
cd /d "%PROJECT_ROOT%"
dart run tool/setup.dart --windows
if errorlevel 1 (
  echo Setup failed. Please check the error above.
  exit /b 1
)

REM 3. Set environment variables for this session
echo.
echo Step 3: Setting environment variables for this session...
set "FFMPEG_DIR=%PROJECT_ROOT%\third_party\generated\ffmpeg_install\windows\x86_64"
set "LIBHEIF_DIR=%PROJECT_ROOT%\third_party\generated\libheif_install\windows\x86_64"
set "PKG_CONFIG_PATH=%LIBHEIF_DIR%\lib\pkgconfig;%FFMPEG_DIR%\lib\pkgconfig"
set "PKG_CONFIG_ALLOW_CROSS=1"
set "PKG_CONFIG_ALLOW_SYSTEM_LIBS=1"

echo   FFMPEG_DIR=%FFMPEG_DIR%
echo   LIBHEIF_DIR=%LIBHEIF_DIR%
echo   PKG_CONFIG_PATH=%PKG_CONFIG_PATH%
echo.

REM 4. Run Rust tests
echo Step 4: Running Rust tests...
cd /d "%PROJECT_ROOT%\native"
cargo test --lib test_concurrent_operations -- --nocapture
if errorlevel 1 (
  echo Rust concurrency test failed or skipped
)

cargo test --lib test_estimate_vs_actual_accuracy -- --nocapture
if errorlevel 1 (
  echo Rust estimate accuracy test failed or skipped
)

REM 5. Run Flutter tests
echo.
echo Step 5: Running Flutter integration tests...
cd /d "%PROJECT_ROOT%\example"
call flutter clean
call flutter pub get

if not "%TEST_VIDEO%"=="" set "TEST_VIDEO_PATH=%TEST_VIDEO%"

echo.
echo --- Test 1: Estimate Accuracy ---
call flutter test integration_test/compression_estimate_test.dart

echo.
echo --- Test 2: Concurrency ---
call flutter test integration_test/concurrency_test.dart

echo.
echo --- Test 3: Comprehensive ---
call flutter test integration_test/comprehensive_test.dart

echo.
echo === All tests complete ===

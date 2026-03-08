@echo off
REM Build Rust libs, clean Flutter, rebuild, and run compression estimate integration test.
REM Usage: tool\test_integration.bat [platform] [test_video_path]
REM Example: tool\test_integration.bat windows C:\path\to\sample.mp4

setlocal
set "SCRIPT_DIR=%~dp0"
set "PROJECT_ROOT=%SCRIPT_DIR%.."
set "PLATFORM=%~1"
set "TEST_VIDEO=%~2"

if "%PLATFORM%"=="" set "PLATFORM=windows"

echo === Integration test: Build and test compression estimate ===
echo Platform: %PLATFORM%
echo Test video: %TEST_VIDEO%
echo.

cd /d "%PROJECT_ROOT%"

REM 1. Build native libraries
echo ^>^>^> Building Rust native libraries...
dart run tool/setup.dart --%PLATFORM%
if errorlevel 1 (
  echo Setup failed. Ensure FFmpeg and dependencies are available.
  exit /b 1
)

REM 2. Clean Flutter build
echo ^>^>^> Cleaning Flutter build...
cd example
call flutter clean

REM 3. Get dependencies
echo ^>^>^> Getting dependencies...
call flutter pub get

REM 4. Run integration test
echo ^>^>^> Running integration test...
if not "%TEST_VIDEO%"=="" set "TEST_VIDEO_PATH=%TEST_VIDEO%"
REM TEST_VIDEO_PATH is used by the Dart integration test
call flutter test integration_test/compression_estimate_test.dart

echo.
echo === Integration test complete ===

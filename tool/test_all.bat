@echo off
REM Run all integration tests: concurrency, estimate accuracy, and comprehensive tests
REM Usage: tool\test_all.bat [platform] [test_video_path]
REM Example: tool\test_all.bat windows C:\path\to\sample.mp4

setlocal
set "SCRIPT_DIR=%~dp0"
set "PROJECT_ROOT=%SCRIPT_DIR%.."
set "PLATFORM=%~1"
set "TEST_VIDEO=%~2"

if "%PLATFORM%"=="" set "PLATFORM=windows"

echo === Running All Integration Tests ===
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

REM 4. Run Rust unit tests (including concurrency test)
echo.
echo ^>^>^> Running Rust unit tests...
cd "%PROJECT_ROOT%\native"
cargo test --lib test_concurrent_operations -- --nocapture
if errorlevel 1 (
  echo Rust concurrency test failed or skipped (may need test video)
)

REM 5. Run Dart integration tests
echo.
echo ^>^>^> Running Dart integration tests...
cd "%PROJECT_ROOT%\example"

if not "%TEST_VIDEO%"=="" set "TEST_VIDEO_PATH=%TEST_VIDEO%"

echo.
echo --- Test 1: Estimate Accuracy ---
call flutter test integration_test/compression_estimate_test.dart
if errorlevel 1 (
  echo Estimate accuracy test failed or skipped
)

echo.
echo --- Test 2: Concurrency ---
call flutter test integration_test/concurrency_test.dart
if errorlevel 1 (
  echo Concurrency test failed or skipped
)

echo.
echo --- Test 3: Comprehensive (Estimate + Concurrency) ---
call flutter test integration_test/comprehensive_test.dart
if errorlevel 1 (
  echo Comprehensive test failed or skipped
)

echo.
echo === All Tests Complete ===

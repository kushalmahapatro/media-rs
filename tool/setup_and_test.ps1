# Setup environment and run tests
# Usage: .\tool\setup_and_test.ps1 [test_video_path]

param(
    [string]$TestVideo = ""
)

$ErrorActionPreference = "Continue"

$PROJECT_ROOT = $PSScriptRoot + "\.."
$PROJECT_ROOT = (Resolve-Path $PROJECT_ROOT).Path

Write-Host "=== Setting up environment and running tests ==="
Write-Host ""

# Step 1: Setup environment variables
Write-Host "Step 1: Setting up environment variables..."
$env:FFMPEG_DIR = "$PROJECT_ROOT\third_party\generated\ffmpeg_install\windows\x86_64"
$env:LIBHEIF_DIR = "$PROJECT_ROOT\third_party\generated\libheif_install\windows\x86_64"
$env:PKG_CONFIG_PATH = "$env:LIBHEIF_DIR\lib\pkgconfig;$env:FFMPEG_DIR\lib\pkgconfig"
$env:PKG_CONFIG_ALLOW_CROSS = "1"
$env:PKG_CONFIG_ALLOW_SYSTEM_LIBS = "1"

Write-Host "  FFMPEG_DIR: $env:FFMPEG_DIR"
Write-Host "  LIBHEIF_DIR: $env:LIBHEIF_DIR"
Write-Host "  PKG_CONFIG_PATH: $env:PKG_CONFIG_PATH"
Write-Host ""

# Step 2: Build libraries if needed (optional - comment out if already built)
# Write-Host "Step 2: Building libraries (if needed)..."
# Set-Location $PROJECT_ROOT
# dart run tool/setup.dart --windows
# if ($LASTEXITCODE -ne 0) {
#     Write-Host "Setup failed. Please check the error above."
#     exit 1
# }

# Step 3: Run Rust tests
Write-Host "Step 3: Running Rust tests..."
Set-Location "$PROJECT_ROOT\native"

Write-Host ""
Write-Host "--- Test: Concurrent Operations ---"
cargo test --lib test_concurrent_operations -- --nocapture
if ($LASTEXITCODE -ne 0) {
    Write-Host "Rust concurrency test failed or skipped"
}

Write-Host ""
Write-Host "--- Test: Estimate vs Actual Accuracy ---"
cargo test --lib test_estimate_vs_actual_accuracy -- --nocapture
if ($LASTEXITCODE -ne 0) {
    Write-Host "Rust estimate accuracy test failed or skipped"
}

# Step 4: Run Flutter tests
Write-Host ""
Write-Host "Step 4: Running Flutter integration tests..."
Set-Location "$PROJECT_ROOT\example"

flutter clean
flutter pub get

if ($TestVideo -ne "") {
    $env:TEST_VIDEO_PATH = $TestVideo
}

Write-Host ""
Write-Host "--- Test 1: Estimate Accuracy ---"
flutter test integration_test/compression_estimate_test.dart

Write-Host ""
Write-Host "--- Test 2: Concurrency ---"
flutter test integration_test/concurrency_test.dart

Write-Host ""
Write-Host "--- Test 3: Comprehensive ---"
flutter test integration_test/comprehensive_test.dart

Write-Host ""
Write-Host "=== All tests complete ==="

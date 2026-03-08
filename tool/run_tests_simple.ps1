# Simple PowerShell script to run tests
$env:FFMPEG_DIR = "D:\media-rs\media-rs\third_party\generated\ffmpeg_install\windows\x86_64"
$env:LIBHEIF_DIR = "D:\media-rs\media-rs\third_party\generated\libheif_install\windows\x86_64"
$env:PKG_CONFIG_PATH = "$env:LIBHEIF_DIR\lib\pkgconfig;$env:FFMPEG_DIR\lib\pkgconfig"
$env:PKG_CONFIG_ALLOW_CROSS = "1"
$env:PKG_CONFIG_ALLOW_SYSTEM_LIBS = "1"
Write-Host "Environment variables set"
cd D:\media-rs\media-rs\native
cargo test --lib test_concurrent_operations -- --nocapture

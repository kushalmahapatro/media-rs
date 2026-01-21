@echo off
REM Setup environment variables for Windows builds
REM Usage: setup_env.bat

setlocal

REM Get the project root directory (parent of native/)
set "SCRIPT_DIR=%~dp0"
set "PROJECT_ROOT=%SCRIPT_DIR%.."

REM Set library directories
set "FFMPEG_DIR=%PROJECT_ROOT%\third_party\generated\ffmpeg_install\windows\x86_64"
set "LIBHEIF_DIR=%PROJECT_ROOT%\third_party\generated\libheif_install\windows\x86_64"
set "OPENH264_DIR=%PROJECT_ROOT%\third_party\generated\openh264_install\windows\x86_64"

REM Set pkg-config paths
set "PKG_CONFIG_PATH=%LIBHEIF_DIR%\lib\pkgconfig;%FFMPEG_DIR%\lib\pkgconfig"
set "PKG_CONFIG_ALLOW_CROSS=1"
set "PKG_CONFIG_ALLOW_SYSTEM_LIBS=1"

echo Environment variables set:
echo   FFMPEG_DIR=%FFMPEG_DIR%
echo   LIBHEIF_DIR=%LIBHEIF_DIR%
echo   OPENH264_DIR=%OPENH264_DIR%
echo   PKG_CONFIG_PATH=%PKG_CONFIG_PATH%
echo.
echo To use these variables in this shell, run:
echo   call setup_env.bat
echo.
echo Or to set them permanently for this session:
echo   setx FFMPEG_DIR "%FFMPEG_DIR%"
echo   setx LIBHEIF_DIR "%LIBHEIF_DIR%"
echo   setx OPENH264_DIR "%OPENH264_DIR%"

endlocal

@echo off
setlocal EnableExtensions EnableDelayedExpansion

rem Windows entrypoint (repo root) - replaces setup_all.ps1.
rem IMPORTANT: Run this script from Windows CMD or PowerShell, NOT from bash/MINGW64 shell.
rem If you see "unexpected at this time" error, you are running from bash.
rem Solution: Open Windows CMD and run the script from there.
rem Uses MSYS2 bash to run the supporting scripts under scripts/support/.
rem
rem Prereqs:
rem - MSYS2 installed at C:\msys64 (or set MSYS2_ROOT)
rem - Rust + Flutter installed
rem
rem NOTE: This script should be run from Windows CMD or PowerShell, not from bash/MINGW64 shell.

set "REPO_ROOT=%~dp0"
rem strip trailing backslash
if "%REPO_ROOT:~-1%"=="\" set "REPO_ROOT=%REPO_ROOT:~0,-1%"

set "MSYS2_ROOT=%MSYS2_ROOT%"
if "%MSYS2_ROOT%"=="" set "MSYS2_ROOT=C:\msys64"
set "BASH=%MSYS2_ROOT%\usr\bin\bash.exe"
set "PACMAN=%MSYS2_ROOT%\usr\bin\pacman.exe"
set "MINGW64_SHELL=%MSYS2_ROOT%\mingw64.exe"

rem Check if MSYS2 is installed
if not exist "%BASH%" (
  echo.
  echo ========================================
  echo ERROR: MSYS2 not found at "%MSYS2_ROOT%"
  echo ========================================
  echo.
  echo MSYS2 is required for building Windows dependencies.
  echo.
  echo To install MSYS2:
  echo   1. Download from: https://www.msys2.org/
  echo   2. Run the installer and install to: %MSYS2_ROOT%
  echo   3. After installation, open "MinGW-w64 Win64 Shell" from Start Menu
  echo   4. Run: pacman -Syu
  echo   5. Close and reopen the shell, then run: pacman -Su
  echo   6. Then run this script again
  echo.
  echo Alternatively, if MSYS2 is installed elsewhere, set MSYS2_ROOT:
  echo   set MSYS2_ROOT=C:\path\to\msys64
  echo   setup_all.bat --windows
  echo.
  exit /b 2
)

echo MSYS2 found at: %MSYS2_ROOT%

set "DO_ANDROID=0"
set "DO_WINDOWS=0"
set "SKIP_OPENH264=0"
set "DO_ALL=0"

if "%~1"=="" (
  set "DO_WINDOWS=1"
) else (
  :parse_args
  if "%~1"=="" goto args_done
  if /I "%~1"=="--all" (
    set "DO_ALL=1"
  ) else if /I "%~1"=="--android" (
    set "DO_ANDROID=1"
  ) else if /I "%~1"=="--windows" (
    set "DO_WINDOWS=1"
  ) else if /I "%~1"=="--skip-openh264" (
    set "SKIP_OPENH264=1"
  ) else if /I "%~1"=="-h" (
    goto usage
  ) else if /I "%~1"=="--help" (
    goto usage
  ) else (
    echo Unknown arg: %~1
    goto usage
  )
  shift
  goto parse_args
)

goto :args_done
:args_done
if "%DO_ALL%"=="1" (
  set "DO_ANDROID=1"
  set "DO_WINDOWS=1"
)

if "%DO_ANDROID%"=="1" (
  if "%ANDROID_NDK_HOME%"=="" (
    echo ERROR: ANDROID_NDK_HOME must be set for Android builds.
    exit /b 2
  )
)

pushd "%REPO_ROOT%" >nul
if errorlevel 1 (
  echo ERROR: Failed to change to repository root: %REPO_ROOT%
  exit /b 2
)

rem Check and install required MSYS2 packages for Windows builds
if "%DO_WINDOWS%"=="1" (
  echo.
  echo === Checking MSYS2 packages for Windows builds ===
  echo.
  echo NOTE: Please ensure the following packages are installed:
  echo   mingw-w64-x86_64-gcc mingw-w64-x86_64-nasm mingw-w64-x86_64-pkgconf mingw-w64-x86_64-cmake make git
  echo.
  echo To install them, open "MinGW-w64 Win64 Shell" and run:
  echo   pacman -S --needed mingw-w64-x86_64-gcc mingw-w64-x86_64-nasm mingw-w64-x86_64-pkgconf mingw-w64-x86_64-cmake make git
  echo.
  echo Note: pkgconf is used instead of pkg-config (it provides pkg-config compatibility)
  echo.
  echo Continuing with build...
  echo.
)
echo Package check completed
echo.
echo Setting up build arguments...
set EXTRA_ARGS=
if "%SKIP_OPENH264%"=="1" set EXTRA_ARGS=--skip-openh264
echo Build arguments configured
echo.
echo Starting Windows build process...
if not "%DO_WINDOWS%"=="1" goto skip_windows_build
  echo === Windows (via MSYS2): openh264 ===
  "%BASH%" -lc "cd /d/media-rs/media-rs && export PATH=/mingw64/bin:/usr/bin:\$PATH && ./scripts/support/setup_openh264_windows.sh"
  if errorlevel 1 (
    echo ERROR: OpenH264 build failed. Check the output above.
    goto fail
  )

  echo === Windows (via MSYS2): ffmpeg (+openh264) ===
  if "%SKIP_OPENH264%"=="1" (
    echo ERROR: Windows FFmpeg build requires OpenH264. Cannot skip.
    exit /b 2
  )
  "%BASH%" -lc "cd /d/media-rs/media-rs && export PATH=/mingw64/bin:/usr/bin:\$PATH && ./scripts/support/setup_ffmpeg_windows.sh"
  if errorlevel 1 goto fail

  echo === Windows (via MSYS2): libheif ===
  "%BASH%" -lc "cd /d/media-rs/media-rs && export PATH=/mingw64/bin:/usr/bin:\$PATH && ./scripts/support/setup_libheif_windows.sh"
  if errorlevel 1 goto fail

  echo.
  echo === Windows: Converting libheif to MSVC format ===
  echo.
  echo NOTE: MinGW-built libheif has COMDAT incompatibility with MSVC linker.
  echo Building libheif with MSVC to fix this issue...
  echo This will take 10-15 minutes.
  echo.
  
  rem Run MSVC build script (automatically sets up VS environment)
  echo Running MSVC build script...
  call "%REPO_ROOT%\scripts\support\build_libheif_msvc.bat"
  if errorlevel 1 (
    echo.
    echo WARNING: MSVC build failed or Visual Studio not found.
    echo.
    echo The MinGW-built libraries are installed, but they may have COMDAT issues.
    echo To fix this, you can:
    echo   1. Install Visual Studio 2022 with C++ development tools
    echo   2. Run manually: scripts\support\build_libheif_msvc.bat
    echo.
    echo Continuing with MinGW-built libraries (may cause linker errors)...
    echo.
  ) else (
    echo.
    echo ========================================
    echo SUCCESS: MSVC-built libheif installed!
    echo ========================================
    echo.
    echo The MSVC-compatible libraries are now ready.
    echo You can now run: flutter build windows
    echo.
  )
:skip_windows_build

popd >nul
exit /b 0

:usage
echo Usage:
echo   setup_all.bat [--all] [--android] [--windows] [--skip-openh264]
echo.
echo Defaults:
echo   - If no args are provided, builds Windows dependencies.
echo.
echo Env:
echo   - MSYS2_ROOT (optional, default C:\msys64)
echo   - ANDROID_NDK_HOME (required for --android)
exit /b 2

:fail
set "EC=%ERRORLEVEL%"
popd >nul
exit /b %EC%


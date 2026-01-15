@echo off
setlocal EnableExtensions EnableDelayedExpansion

rem Windows entrypoint (repo root) - replaces setup_all.ps1.
rem Uses MSYS2 bash to run the supporting scripts under scripts/support/.
rem
rem Prereqs:
rem - MSYS2 installed at C:\msys64 (or set MSYS2_ROOT)
rem - Rust + Flutter installed

set "REPO_ROOT=%~dp0"
rem strip trailing backslash
if "%REPO_ROOT:~-1%"=="\" set "REPO_ROOT=%REPO_ROOT:~0,-1%"

set "MSYS2_ROOT=%MSYS2_ROOT%"
if "%MSYS2_ROOT%"=="" set "MSYS2_ROOT=C:\msys64"
set "BASH=%MSYS2_ROOT%\usr\bin\bash.exe"

if not exist "%BASH%" (
  echo ERROR: MSYS2 bash not found at "%BASH%"
  echo Install MSYS2 or set MSYS2_ROOT.
  exit /b 2
)

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

set "EXTRA_ARGS="
if "%SKIP_OPENH264%"=="1" set "EXTRA_ARGS=--skip-openh264"

if "%DO_ANDROID%"=="1" (
  echo === Android (via MSYS2): ffmpeg (+openh264) ===
  "%BASH%" -lc "./scripts/support/setup_ffmpeg_android.sh %EXTRA_ARGS%"
  if errorlevel 1 goto fail

  echo === Android (via MSYS2): libheif ===
  "%BASH%" -lc "./scripts/support/setup_libheif_all.sh --android-only"
  if errorlevel 1 goto fail
)

if "%DO_WINDOWS%"=="1" (
  echo NOTE: Windows-native vendored builds are not yet implemented in this repo.
  echo For now, use system deps + env overrides (see SETUP.md).
)

popd >nul
exit /b 0

:usage
echo Usage:
echo   setup_all.bat [--all] [--android] [--windows] [--skip-openh264]
echo.
echo Defaults:
echo   - If no args are provided, it prints the Windows note (no vendored builds yet).
echo.
echo Env:
echo   - MSYS2_ROOT (optional, default C:\msys64)
echo   - ANDROID_NDK_HOME (required for --android)
exit /b 2

:fail
set "EC=%ERRORLEVEL%"
popd >nul
exit /b %EC%



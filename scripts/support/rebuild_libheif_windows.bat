@echo off
REM Quick script to rebuild libheif for Windows
REM This fixes the missing libheif.a issue

echo ========================================
echo Rebuilding libheif for Windows
echo ========================================
echo.

set "MSYS2_ROOT=%MSYS2_ROOT%"
if "%MSYS2_ROOT%"=="" set "MSYS2_ROOT=C:\msys64"
set "BASH=%MSYS2_ROOT%\usr\bin\bash.exe"

if not exist "%BASH%" (
    echo ERROR: MSYS2 not found at %MSYS2_ROOT%
    echo Please install MSYS2 or set MSYS2_ROOT environment variable
    exit /b 1
)

echo Using MSYS2 at: %MSYS2_ROOT%
echo.

REM Convert Windows path to Unix path for bash
set "REPO_ROOT=%~dp0..\.."
set "REPO_ROOT=%REPO_ROOT:\=/%"
set "REPO_ROOT=%REPO_ROOT:~0,-1%"

echo Running libheif build script...
"%BASH%" -lc "cd %REPO_ROOT% && export PATH=/mingw64/bin:/usr/bin:\$PATH && bash scripts/support/setup_libheif_windows.sh"

if %errorLevel% equ 0 (
    echo.
    echo ========================================
    echo Checking if libheif.a was installed...
    echo ========================================
    if exist "%~dp0..\..\third_party\libheif_install\windows\x86_64\lib\libheif.a" (
        echo.
        echo SUCCESS: libheif.a is now installed!
        echo You can now run 'flutter run -d windows' again.
    ) else (
        echo.
        echo WARNING: libheif.a still not found after build.
        echo Check the build output above for errors.
    )
) else (
    echo.
    echo ERROR: Build failed with exit code %errorLevel%
    echo Check the output above for details.
)

echo.
pause

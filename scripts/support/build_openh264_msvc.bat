@echo off
setlocal EnableExtensions EnableDelayedExpansion

REM Build OpenH264 with MSVC (Visual Studio)
REM This fixes the COMDAT incompatibility issue
REM Works on controlled Windows machines without PowerShell

set "REPO_ROOT=%~dp0..\.."
set "THIRD_PARTY_DIR=%REPO_ROOT%\third_party"
set "SOURCE_DIR=%THIRD_PARTY_DIR%\sources"
set "INSTALL_DIR=%THIRD_PARTY_DIR%\openh264_install\windows\x86_64"

echo ========================================
echo Building OpenH264 with MSVC (Visual Studio)
echo ========================================
echo.
echo This will build OpenH264 using MSVC instead of MinGW
echo to fix COMDAT incompatibility issues.
echo.

REM Find Visual Studio installation
echo Searching for Visual Studio installation...

set "VS_PATH="
set "VS_FOUND=0"

REM Try common locations
if exist "C:\Program Files\Microsoft Visual Studio\2022\Community\VC\Auxiliary\Build\vcvars64.bat" (
    set "VS_PATH=C:\Program Files\Microsoft Visual Studio\2022\Community\VC\Auxiliary\Build\vcvars64.bat"
    set "VS_FOUND=1"
) else if exist "C:\Program Files\Microsoft Visual Studio\2022\Professional\VC\Auxiliary\Build\vcvars64.bat" (
    set "VS_PATH=C:\Program Files\Microsoft Visual Studio\2022\Professional\VC\Auxiliary\Build\vcvars64.bat"
    set "VS_FOUND=1"
) else if exist "C:\Program Files\Microsoft Visual Studio\2022\Enterprise\VC\Auxiliary\Build\vcvars64.bat" (
    set "VS_PATH=C:\Program Files\Microsoft Visual Studio\2022\Enterprise\VC\Auxiliary\Build\vcvars64.bat"
    set "VS_FOUND=1"
) else if exist "C:\Program Files (x86)\Microsoft Visual Studio\2022\Community\VC\Auxiliary\Build\vcvars64.bat" (
    set "VS_PATH=C:\Program Files (x86)\Microsoft Visual Studio\2022\Community\VC\Auxiliary\Build\vcvars64.bat"
    set "VS_FOUND=1"
) else if exist "C:\Program Files (x86)\Microsoft Visual Studio\2022\Professional\VC\Auxiliary\Build\vcvars64.bat" (
    set "VS_PATH=C:\Program Files (x86)\Microsoft Visual Studio\2022\Professional\VC\Auxiliary\Build\vcvars64.bat"
    set "VS_FOUND=1"
) else if exist "C:\Program Files (x86)\Microsoft Visual Studio\2022\Enterprise\VC\Auxiliary\Build\vcvars64.bat" (
    set "VS_PATH=C:\Program Files (x86)\Microsoft Visual Studio\2022\Enterprise\VC\Auxiliary\Build\vcvars64.bat"
    set "VS_FOUND=1"
)

if "%VS_FOUND%"=="0" (
    echo ERROR: Could not find Visual Studio installation.
    echo.
    echo Please ensure Visual Studio 2022 with C++ development tools is installed.
    echo Or run this from Developer Command Prompt for VS 2022.
    echo.
    exit /b 1
)

echo Found Visual Studio at: %VS_PATH%
echo Setting up Visual Studio environment...

REM Set up VS environment by calling vcvars64.bat
REM Temporarily disable delayed expansion to avoid parsing issues, but preserve environment
setlocal DisableDelayedExpansion
call "%VS_PATH%"
echo VS environment setup complete.
echo.

REM Add MSYS2 make and nasm to PATH (OpenH264 build requires both)
if exist "C:\msys64\usr\bin\make.exe" (
    set "PATH=C:\msys64\usr\bin;%PATH%"
    echo Added MSYS2 make to PATH
) else if exist "C:\msys64\mingw64\bin\make.exe" (
    set "PATH=C:\msys64\mingw64\bin;%PATH%"
    echo Added MSYS2 MinGW make to PATH
)

REM Add nasm to PATH (required for assembly optimizations)
set "USE_ASM=Yes"
if exist "C:\msys64\mingw64\bin\nasm.exe" (
    REM nasm is already in PATH from make check above, but verify
    where nasm >nul 2>&1
    if errorLevel 1 (
        set "PATH=C:\msys64\mingw64\bin;%PATH%"
    )
    echo Added nasm to PATH
) else if exist "C:\msys64\usr\bin\nasm.exe" (
    set "PATH=C:\msys64\usr\bin;%PATH%"
    echo Added nasm to PATH
) else (
    echo WARNING: nasm not found. Assembly optimizations will be disabled.
    echo Install nasm with: pacman -S mingw-w64-x86_64-nasm
    echo Building without assembly optimizations...
    set "USE_ASM=No"
)

echo Proceeding with build...
echo.

REM Create directories
if not exist "%SOURCE_DIR%" mkdir "%SOURCE_DIR%"
if not exist "%INSTALL_DIR%\lib" mkdir "%INSTALL_DIR%\lib"
if not exist "%INSTALL_DIR%\include\wels" mkdir "%INSTALL_DIR%\include\wels"
if not exist "%INSTALL_DIR%\lib\pkgconfig" mkdir "%INSTALL_DIR%\lib\pkgconfig"

cd /d "%SOURCE_DIR%"

REM Clone OpenH264 if needed
if not exist "openh264" (
    echo Cloning OpenH264...
    git clone https://github.com/cisco/openh264.git
    if errorLevel 1 (
        echo ERROR: Failed to clone OpenH264
        exit /b 1
    )
)

cd /d "%SOURCE_DIR%\openh264"
git checkout master 2>nul || true

echo.
echo ========================================
echo Building OpenH264 with MSVC...
echo ========================================

echo Cleaning previous build...
if "!USE_ASM!"=="No" (
    make OS=msvc ARCH=x86_64 USE_ASM=No BUILDTYPE=Release clean 2>nul
) else (
    make OS=msvc ARCH=x86_64 USE_ASM=Yes BUILDTYPE=Release clean 2>nul
)
if errorlevel 1 (
    echo Note: Clean may have failed (this is OK if no previous build exists)
)

echo Building OpenH264 static library...
if "!USE_ASM!"=="No" (
    make OS=msvc ARCH=x86_64 USE_ASM=No BUILDTYPE=Release
) else (
    make OS=msvc ARCH=x86_64 USE_ASM=Yes BUILDTYPE=Release
)
if errorLevel 1 (
    echo ERROR: Build failed for OpenH264
    exit /b 1
)

REM Check for the built library (MSVC generates openh264.lib)
if exist "openh264.lib" (
    echo Found openh264.lib
    copy /Y "openh264.lib" "%INSTALL_DIR%\lib\libopenh264.lib"
    copy /Y "openh264.lib" "%INSTALL_DIR%\lib\openh264.lib"
    echo Installed openh264.lib
) else if exist "libopenh264.lib" (
    echo Found libopenh264.lib
    copy /Y "libopenh264.lib" "%INSTALL_DIR%\lib\libopenh264.lib"
    copy /Y "libopenh264.lib" "%INSTALL_DIR%\lib\openh264.lib"
    echo Installed libopenh264.lib
) else (
    echo ERROR: openh264.lib not found after build
    echo Searched for: openh264.lib, libopenh264.lib
    exit /b 1
)

REM Copy headers
if exist "codec\api\wels" (
    xcopy /Y "codec\api\wels\*.h" "%INSTALL_DIR%\include\wels\" >nul 2>&1
    echo Headers copied
)

REM Create pkg-config file
(
echo prefix=%INSTALL_DIR:\=/%
echo exec_prefix=%%{prefix}
echo libdir=%%{exec_prefix}/lib
echo includedir=%%{prefix}/include
echo.
echo Name: openh264
echo Description: OpenH264 is a codec library which supports H.264 encoding and decoding
echo Version: 2.6.0
echo Libs: -L%%{libdir} -lopenh264
echo Cflags: -I%%{includedir}
) > "%INSTALL_DIR%\lib\pkgconfig\openh264.pc"

echo.
echo ========================================
echo SUCCESS: OpenH264 built with MSVC!
echo ========================================
echo.
echo Library installed to: %INSTALL_DIR%\lib
echo.
echo You can now run: flutter build windows
echo.

endlocal

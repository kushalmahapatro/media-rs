@echo off
setlocal EnableExtensions EnableDelayedExpansion

REM Build libheif with MSVC (Visual Studio)
REM This fixes the COMDAT incompatibility issue
REM Works on controlled Windows machines without PowerShell

set "REPO_ROOT=%~dp0..\.."
set "THIRD_PARTY_DIR=%REPO_ROOT%\third_party"
set "SOURCE_DIR=%THIRD_PARTY_DIR%\sources"
set "INSTALL_DIR=%THIRD_PARTY_DIR%\libheif_install\windows\x86_64"
set "BUILD_DIR=%THIRD_PARTY_DIR%\libheif_build_windows_msvc_x86_64"
set "DE265_INSTALL=%BUILD_DIR%\libde265_install"

echo ========================================
echo Building libheif with MSVC (Visual Studio)
echo ========================================
echo.
echo This will build libheif using MSVC instead of MinGW
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
REM Don't call endlocal - we need the VS environment variables to persist
REM The outer setlocal with EnableDelayedExpansion will handle cleanup at script end

REM Note: We skip explicit verification - if tools aren't available, the build will fail naturally
echo Proceeding with build...
echo.

REM Create directories
if not exist "%SOURCE_DIR%" mkdir "%SOURCE_DIR%"
if not exist "%BUILD_DIR%" mkdir "%BUILD_DIR%"
if not exist "%INSTALL_DIR%\lib" mkdir "%INSTALL_DIR%\lib"
if not exist "%INSTALL_DIR%\include" mkdir "%INSTALL_DIR%\include"

cd /d "%SOURCE_DIR%"

REM Build libde265
echo ========================================
echo Building libde265 with MSVC...
echo ========================================

if not exist "libde265" (
    echo Cloning libde265...
    git clone --depth 1 --branch v1.0.15 https://github.com/strukturag/libde265.git
    if errorLevel 1 (
        echo ERROR: Failed to clone libde265
        exit /b 1
    )
)

cd /d "%SOURCE_DIR%\libde265"
if exist build_msvc rmdir /s /q build_msvc
mkdir build_msvc
cd build_msvc

echo Configuring libde265 with CMake...
cmake .. ^
  -G "Visual Studio 17 2022" ^
  -A x64 ^
  -DCMAKE_BUILD_TYPE=Release ^
  -DCMAKE_INSTALL_PREFIX="%DE265_INSTALL%" ^
  -DCMAKE_MSVC_RUNTIME_LIBRARY=MultiThreadedDLL ^
  -DBUILD_SHARED_LIBS=OFF ^
  -DENABLE_SDL=OFF ^
  -DENABLE_DEC265=OFF ^
  -DENABLE_ENCODER=OFF

if errorLevel 1 (
    echo ERROR: CMake configuration failed for libde265
    exit /b 1
)

echo Building libde265...
cmake --build . --config Release --target de265
if errorLevel 1 (
    echo ERROR: Build failed for libde265
    exit /b 1
)

echo Installing libde265...
cmake --install . --config Release --component de265
if errorLevel 1 (
    echo WARNING: cmake install failed, trying manual copy...
    REM Try multiple possible locations
    if exist "libde265\Release\libde265.lib" (
        if not exist "%DE265_INSTALL%\lib" mkdir "%DE265_INSTALL%\lib"
        copy /Y "libde265\Release\libde265.lib" "%DE265_INSTALL%\lib\"
    ) else if exist "Release\libde265.lib" (
        if not exist "%DE265_INSTALL%\lib" mkdir "%DE265_INSTALL%\lib"
        copy /Y "Release\libde265.lib" "%DE265_INSTALL%\lib\"
    ) else if exist "x64\Release\libde265.lib" (
        if not exist "%DE265_INSTALL%\lib" mkdir "%DE265_INSTALL%\lib"
        copy /Y "x64\Release\libde265.lib" "%DE265_INSTALL%\lib\"
    )
)

REM Also copy headers if available
if exist "..\libde265\libde265" (
    if not exist "%DE265_INSTALL%\include\libde265" mkdir "%DE265_INSTALL%\include\libde265"
    xcopy /E /I /Y "..\libde265\libde265\*.h" "%DE265_INSTALL%\include\libde265\" >nul 2>&1
)

REM Copy generated version header from build directory (CMake generates this)
if exist "libde265\de265-version.h" (
    if not exist "%DE265_INSTALL%\include\libde265" mkdir "%DE265_INSTALL%\include\libde265"
    copy /Y "libde265\de265-version.h" "%DE265_INSTALL%\include\libde265\"
    echo Copied de265-version.h
)

if not exist "%DE265_INSTALL%\lib\libde265.lib" (
    echo ERROR: libde265.lib not found after build
    echo Searched in: libde265\Release, Release, x64\Release
    exit /b 1
)

echo libde265 build complete!
echo.

REM Build libheif
echo ========================================
echo Building libheif with MSVC...
echo ========================================

cd /d "%SOURCE_DIR%"

REM Download libheif if needed
if not exist "libheif-1.20.2" (
    echo Downloading libheif 1.20.2...
    
    REM Try to use curl (Windows 10+)
    where curl >nul 2>&1
    if not errorLevel 1 (
        curl -L "https://github.com/strukturag/libheif/releases/download/v1.20.2/libheif-1.20.2.tar.gz" -o "libheif-1.20.2.tar.gz"
        if not errorLevel 1 (
            REM Extract using tar (Windows 10+)
            where tar >nul 2>&1
            if not errorLevel 1 (
                tar -xzf libheif-1.20.2.tar.gz
                del libheif-1.20.2.tar.gz
            ) else (
                echo ERROR: tar not found. Please extract libheif-1.20.2.tar.gz manually.
                exit /b 1
            )
        ) else (
            echo ERROR: Failed to download libheif
            exit /b 1
        )
    ) else (
        echo ERROR: curl not found. Please download libheif-1.20.2.tar.gz manually from:
        echo https://github.com/strukturag/libheif/releases/download/v1.20.2/libheif-1.20.2.tar.gz
        echo And extract it to: %SOURCE_DIR%
        exit /b 1
    )
)

cd /d "%SOURCE_DIR%\libheif-1.20.2"
if exist build_msvc rmdir /s /q build_msvc
mkdir build_msvc
cd build_msvc

echo Configuring libheif with CMake...
cmake .. ^
  -G "Visual Studio 17 2022" ^
  -A x64 ^
  -DCMAKE_BUILD_TYPE=Release ^
  -DCMAKE_INSTALL_PREFIX="%BUILD_DIR%" ^
  -DCMAKE_MSVC_RUNTIME_LIBRARY=MultiThreadedDLL ^
  -DBUILD_SHARED_LIBS=OFF ^
  -DENABLE_PLUGIN_LOADING=OFF ^
  -DWITH_AOM=OFF ^
  -DWITH_DAV1D=OFF ^
  -DWITH_RAV1E=OFF ^
  -DWITH_X265=OFF ^
  -DWITH_LIBDE265=ON ^
  -DLIBDE265_INCLUDE_DIR="%DE265_INSTALL%\include" ^
  -DLIBDE265_LIBRARY="%DE265_INSTALL%\lib\libde265.lib" ^
  -DCMAKE_C_FLAGS="/DLIBDE265_STATIC_BUILD" ^
  -DCMAKE_CXX_FLAGS="/DLIBDE265_STATIC_BUILD" ^
  -DWITH_EXAMPLES=OFF ^
  -DWITH_TESTS=OFF ^
  -DWITH_UNCOMPRESSED_CODEC=OFF ^
  -DCMAKE_DISABLE_FIND_PACKAGE_AOM=ON ^
  -DCMAKE_DISABLE_FIND_PACKAGE_libsharpyuv=ON

if errorLevel 1 (
    echo ERROR: CMake configuration failed for libheif
    exit /b 1
)

echo Building libheif...
cmake --build . --config Release --target heif
if errorLevel 1 (
    echo ERROR: Build failed for libheif
    exit /b 1
)

echo Installing libheif...
cmake --install . --config Release --component libheif
if errorLevel 1 (
    echo WARNING: cmake install failed, trying manual copy...
    REM Try both heif.lib and libheif.lib (MSVC generates heif.lib)
    if exist "libheif\Release\heif.lib" (
        if not exist "%BUILD_DIR%\lib" mkdir "%BUILD_DIR%\lib"
        copy /Y "libheif\Release\heif.lib" "%BUILD_DIR%\lib\heif.lib"
    ) else if exist "libheif\Release\libheif.lib" (
        if not exist "%BUILD_DIR%\lib" mkdir "%BUILD_DIR%\lib"
        copy /Y "libheif\Release\libheif.lib" "%BUILD_DIR%\lib\libheif.lib"
    )
)

REM Ensure install directory exists
if not exist "%INSTALL_DIR%\lib" mkdir "%INSTALL_DIR%\lib"

REM Copy to install directory - check for both heif.lib and libheif.lib
REM First try direct copy from build directory (most reliable, we're in build_msvc)
set "LIBHEIF_COPIED=0"
if exist "libheif\Release\heif.lib" (
    copy /Y "libheif\Release\heif.lib" "%INSTALL_DIR%\lib\libheif.lib" >nul 2>&1
    copy /Y "libheif\Release\heif.lib" "%INSTALL_DIR%\lib\heif.lib" >nul 2>&1
    set "LIBHEIF_COPIED=1"
    echo Installed libheif.lib (direct copy from build)
) else if exist "%BUILD_DIR%\lib\heif.lib" (
    copy /Y "%BUILD_DIR%\lib\heif.lib" "%INSTALL_DIR%\lib\libheif.lib" >nul 2>&1
    copy /Y "%BUILD_DIR%\lib\heif.lib" "%INSTALL_DIR%\lib\heif.lib" >nul 2>&1
    set "LIBHEIF_COPIED=1"
    echo Installed libheif.lib (from BUILD_DIR)
) else if exist "%BUILD_DIR%\lib\libheif.lib" (
    copy /Y "%BUILD_DIR%\lib\libheif.lib" "%INSTALL_DIR%\lib\libheif.lib" >nul 2>&1
    copy /Y "%BUILD_DIR%\lib\libheif.lib" "%INSTALL_DIR%\lib\heif.lib" >nul 2>&1
    set "LIBHEIF_COPIED=1"
    echo Installed libheif.lib
)

REM Verify installation using absolute path
if "!LIBHEIF_COPIED!"=="0" (
    echo ERROR: libheif.lib not found after build
    echo Searched in: libheif\Release\heif.lib, %BUILD_DIR%\lib\heif.lib, %BUILD_DIR%\lib\libheif.lib
    exit /b 1
)

REM Double-check the file actually exists
if not exist "%INSTALL_DIR%\lib\libheif.lib" (
    echo ERROR: Failed to install libheif.lib to %INSTALL_DIR%\lib\
    echo Current directory: %CD%
    exit /b 1
)

REM Copy headers
if exist "%BUILD_DIR%\include\libheif" (
    xcopy /E /I /Y "%BUILD_DIR%\include\libheif" "%INSTALL_DIR%\include\libheif"
)

REM Copy libde265
copy /Y "%DE265_INSTALL%\lib\libde265.lib" "%INSTALL_DIR%\lib\libde265.lib"
copy /Y "%DE265_INSTALL%\lib\libde265.lib" "%INSTALL_DIR%\lib\de265.lib"

if exist "%DE265_INSTALL%\include\libde265" (
    xcopy /E /I /Y "%DE265_INSTALL%\include\libde265" "%INSTALL_DIR%\include\libde265"
)

REM Create pkg-config file
if not exist "%INSTALL_DIR%\lib\pkgconfig" mkdir "%INSTALL_DIR%\lib\pkgconfig"
(
echo prefix=%INSTALL_DIR:\=/%
echo exec_prefix=%%{prefix}
echo libdir=%%{exec_prefix}/lib
echo includedir=%%{prefix}/include
echo.
echo Name: libheif
echo Description: HEIF image codec library
echo Version: 1.20.2
echo Libs: -L%%{libdir} -lheif -lde265
echo Cflags: -I%%{includedir}
echo Requires:
) > "%INSTALL_DIR%\lib\pkgconfig\libheif.pc"

echo.
echo ========================================
echo SUCCESS: libheif built with MSVC!
echo ========================================
echo.
echo Libraries installed to: %INSTALL_DIR%\lib
echo.
echo You can now run: flutter build windows
echo.

endlocal

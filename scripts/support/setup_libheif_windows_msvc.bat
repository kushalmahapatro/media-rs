@echo off
REM Build libheif with MSVC (Visual Studio) instead of MinGW
REM This fixes the COMDAT incompatibility issue

setlocal EnableDelayedExpansion

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

REM Try to find and set up Visual Studio environment
set "VS_PATH=C:\Program Files\Microsoft Visual Studio\2022\Community\VC\Auxiliary\Build\vcvars64.bat"
if not exist "%VS_PATH%" (
    set "VS_PATH=C:\Program Files (x86)\Microsoft Visual Studio\2022\Community\VC\Auxiliary\Build\vcvars64.bat"
)

set "VS_SETUP=0"
if exist "%VS_PATH%" (
    echo Setting up Visual Studio environment...
    call "%VS_PATH%" >nul 2>&1
    if errorLevel 1 (
        echo WARNING: Failed to set up VS environment automatically.
        echo You may need to run this from Developer Command Prompt.
    ) else (
        set "VS_SETUP=1"
    )
)

if "%VS_SETUP%"=="0" (
    echo WARNING: Could not find vcvars64.bat at standard locations.
    echo Trying to find it automatically...
    for /f "delims=" %%i in ('powershell -Command "Get-ChildItem -Path 'C:\Program Files\Microsoft Visual Studio' -Recurse -Filter 'vcvars64.bat' -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty FullName"') do (
        if exist "%%i" (
            echo Found VS at: %%i
            call "%%i" >nul 2>&1
            set "VS_SETUP=1"
        )
    )
)

REM Check for Visual Studio compiler
where cl >nul 2>&1
if %errorLevel% neq 0 (
    echo ERROR: Visual Studio compiler (cl.exe) not found in PATH.
    echo.
    echo Please open "Developer Command Prompt for VS 2022" and run this script from there.
    echo Or manually run vcvars64.bat before running this script.
    echo.
    pause
    exit /b 1
)

echo Found Visual Studio compiler.
echo.

REM Check for CMake
where cmake >nul 2>&1
if %errorLevel% neq 0 (
    echo ERROR: cmake not found in PATH.
    echo Please install CMake and add it to PATH.
    pause
    exit /b 1
)

echo Found CMake.
echo.

REM Create directories
if not exist "%SOURCE_DIR%" mkdir "%SOURCE_DIR%"
if not exist "%BUILD_DIR%" mkdir "%BUILD_DIR%"
if not exist "%INSTALL_DIR%\lib" mkdir "%INSTALL_DIR%\lib"
if not exist "%INSTALL_DIR%\include" mkdir "%INSTALL_DIR%\include"

cd /d "%SOURCE_DIR%"

REM Clone libde265 if needed
if not exist "libde265" (
    echo Cloning libde265...
    git clone --depth 1 --branch v1.0.15 https://github.com/strukturag/libde265.git
    if %errorLevel% neq 0 (
        echo ERROR: Failed to clone libde265
        pause
        exit /b 1
    )
)

REM Build libde265 with MSVC
echo.
echo ========================================
echo Building libde265 with MSVC...
echo ========================================
cd /d "%SOURCE_DIR%\libde265"
if exist build_msvc rmdir /s /q build_msvc
mkdir build_msvc
cd build_msvc

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

if %errorLevel% neq 0 (
    echo ERROR: CMake configuration failed for libde265
    pause
    exit /b 1
)

cmake --build . --config Release --target de265
if %errorLevel% neq 0 (
    echo ERROR: Build failed for libde265
    pause
    exit /b 1
)

REM Install libde265
cmake --install . --config Release --component de265
if %errorLevel% neq 0 (
    echo WARNING: cmake install failed, trying manual copy...
    if exist "Release\libde265.lib" (
        copy /Y "Release\libde265.lib" "%DE265_INSTALL%\lib\"
    )
)

REM Verify libde265.lib exists
if not exist "%DE265_INSTALL%\lib\libde265.lib" (
    echo ERROR: libde265.lib not found after build
    pause
    exit /b 1
)

echo.
echo ========================================
echo Building libheif with MSVC...
echo ========================================

REM Download libheif if needed
cd /d "%SOURCE_DIR%"
if not exist "libheif-1.20.2" (
    echo Downloading libheif 1.20.2...
    curl -L "https://github.com/strukturag/libheif/releases/download/v1.20.2/libheif-1.20.2.tar.gz" | tar xz
    if %errorLevel% neq 0 (
        echo ERROR: Failed to download libheif
        pause
        exit /b 1
    )
)

cd /d "%SOURCE_DIR%\libheif-1.20.2"
if exist build_msvc rmdir /s /q build_msvc
mkdir build_msvc
cd build_msvc

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
  -DWITH_EXAMPLES=OFF ^
  -DWITH_TESTS=OFF ^
  -DWITH_UNCOMPRESSED_CODEC=OFF ^
  -DCMAKE_DISABLE_FIND_PACKAGE_AOM=ON ^
  -DCMAKE_DISABLE_FIND_PACKAGE_libsharpyuv=ON

if %errorLevel% neq 0 (
    echo ERROR: CMake configuration failed for libheif
    pause
    exit /b 1
)

cmake --build . --config Release --target heif
if %errorLevel% neq 0 (
    echo ERROR: Build failed for libheif
    pause
    exit /b 1
)

REM Install libheif
cmake --install . --config Release --component libheif
if %errorLevel% neq 0 (
    echo WARNING: cmake install failed, trying manual copy...
    if exist "libheif\Release\libheif.lib" (
        copy /Y "libheif\Release\libheif.lib" "%BUILD_DIR%\lib\"
    )
)

REM Copy to install directory
if exist "%BUILD_DIR%\lib\libheif.lib" (
    copy /Y "%BUILD_DIR%\lib\libheif.lib" "%INSTALL_DIR%\lib\libheif.lib"
    copy /Y "%BUILD_DIR%\lib\libheif.lib" "%INSTALL_DIR%\lib\heif.lib"
    echo SUCCESS: Copied libheif.lib
) else (
    echo ERROR: libheif.lib not found after build
    pause
    exit /b 1
)

if exist "%BUILD_DIR%\include\libheif" (
    xcopy /E /I /Y "%BUILD_DIR%\include\libheif" "%INSTALL_DIR%\include\libheif"
)

copy /Y "%DE265_INSTALL%\lib\libde265.lib" "%INSTALL_DIR%\lib\libde265.lib"
copy /Y "%DE265_INSTALL%\lib\libde265.lib" "%INSTALL_DIR%\lib\de265.lib"

if exist "%DE265_INSTALL%\include\libde265" (
    xcopy /E /I /Y "%DE265_INSTALL%\include\libde265" "%INSTALL_DIR%\include\libde265"
)

REM Create pkg-config file
if not exist "%INSTALL_DIR%\lib\pkgconfig" mkdir "%INSTALL_DIR%\lib\pkgconfig"
(
echo prefix=%INSTALL_DIR:/=\%
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
echo You can now run: flutter run -d windows
echo.
pause

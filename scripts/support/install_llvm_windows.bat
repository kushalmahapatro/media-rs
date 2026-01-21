@echo off
setlocal EnableExtensions EnableDelayedExpansion

REM Batch script to install LLVM for Windows
REM This is needed for bindgen to generate FFmpeg bindings

echo Checking for LLVM/Clang installation...

REM Check if clang is already in PATH
where clang >nul 2>&1
if not errorLevel 1 (
    for /f "delims=" %%i in ('where clang') do set "CLANG_PATH=%%i"
    echo Found clang at: %CLANG_PATH%
    
    REM Get directory containing clang
    for %%i in ("%CLANG_PATH%") do set "CLANG_DIR=%%~dpi"
    set "CLANG_DIR=%CLANG_DIR:~0,-1%"
    
    if exist "%CLANG_DIR%\clang.dll" (
        echo Setting LIBCLANG_PATH=%CLANG_DIR%
        setx LIBCLANG_PATH "%CLANG_DIR%" >nul 2>&1
        echo LLVM/Clang is ready to use!
        exit /b 0
    )
    if exist "%CLANG_DIR%\libclang.dll" (
        echo Setting LIBCLANG_PATH=%CLANG_DIR%
        setx LIBCLANG_PATH "%CLANG_DIR%" >nul 2>&1
        echo LLVM/Clang is ready to use!
        exit /b 0
    )
)

REM Check common installation paths
set "FOUND_LLVM=0"
if exist "C:\Program Files\LLVM\bin\clang.dll" (
    set "LLVM_BIN=C:\Program Files\LLVM\bin"
    set "FOUND_LLVM=1
) else if exist "C:\Program Files\LLVM\bin\libclang.dll" (
    set "LLVM_BIN=C:\Program Files\LLVM\bin"
    set "FOUND_LLVM=1
) else if exist "C:\Program Files (x86)\LLVM\bin\clang.dll" (
    set "LLVM_BIN=C:\Program Files (x86)\LLVM\bin"
    set "FOUND_LLVM=1
) else if exist "C:\Program Files (x86)\LLVM\bin\libclang.dll" (
    set "LLVM_BIN=C:\Program Files (x86)\LLVM\bin"
    set "FOUND_LLVM=1
)

if "%FOUND_LLVM%"=="1" (
    echo Found LLVM at: %LLVM_BIN%
    setx LIBCLANG_PATH "%LLVM_BIN%" >nul 2>&1
    echo Set LIBCLANG_PATH=%LLVM_BIN%
    echo Please restart your terminal/IDE for changes to take effect.
    exit /b 0
)

echo LLVM/Clang not found. Attempting to install...

REM Try to use winget to install LLVM
where winget >nul 2>&1
if not errorLevel 1 (
    echo Using winget to install LLVM...
    winget install --id LLVM.LLVM --silent --accept-package-agreements --accept-source-agreements
    if not errorLevel 1 (
        echo LLVM installed successfully via winget!
        echo Please restart your terminal/IDE, then run 'flutter run -d windows' again.
        timeout /t 2 /nobreak >nul
        if exist "C:\Program Files\LLVM\bin\clang.dll" (
            setx LIBCLANG_PATH "C:\Program Files\LLVM\bin" >nul 2>&1
            echo Set LIBCLANG_PATH=C:\Program Files\LLVM\bin
        )
        exit /b 0
    ) else (
        echo winget installation failed
    )
)

REM Try to use chocolatey
where choco >nul 2>&1
if not errorLevel 1 (
    echo Using Chocolatey to install LLVM...
    choco install llvm -y
    if not errorLevel 1 (
        echo LLVM installed successfully via Chocolatey!
        echo Please restart your terminal/IDE, then run 'flutter run -d windows' again.
        exit /b 0
    ) else (
        echo Chocolatey installation failed
    )
)

REM Manual installation instructions
echo.
echo Automatic installation failed. Please install LLVM manually:
echo.
echo Option 1: Download and install from:
echo   https://github.com/llvm/llvm-project/releases
echo   Look for: LLVM-*-win64.exe
echo.
echo Option 2: Install via Visual Studio Installer:
echo   1. Open Visual Studio Installer
echo   2. Modify your VS 2022 installation
echo   3. Go to 'Individual components'
echo   4. Search for 'Clang' and check 'MSVC v143 - C++ Clang tools for Windows'
echo   5. Click Modify
echo.
echo After installation, restart your terminal/IDE and run 'flutter run -d windows' again.
exit /b 1

endlocal

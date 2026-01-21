@echo off
REM Convert MinGW .a files to MSVC .lib format using llvm-lib
REM This fixes the COMDAT section incompatibility issue

setlocal EnableDelayedExpansion

set "LIBHEIF_DIR=%~dp0..\..\third_party\libheif_install\windows\x86_64"
set "LLVM_LIB=llvm-lib"

echo ========================================
echo Converting MinGW .a files to MSVC .lib
echo ========================================
echo.

REM Check if llvm-lib is available
where llvm-lib >nul 2>&1
if %errorLevel% neq 0 (
    echo WARNING: llvm-lib not found in PATH.
    echo.
    echo To install LLVM tools:
    echo   1. Install LLVM from: https://github.com/llvm/llvm-project/releases
    echo   2. Or install via Visual Studio Installer: "C++ Clang tools for Windows"
    echo   3. Add LLVM bin directory to PATH
    echo.
    echo Trying alternative approach with /FORCE:MULTIPLE linker flag...
    goto :use_force_multiple
)

echo Found llvm-lib, converting libraries...
echo.

REM Convert libheif.a
if exist "%LIBHEIF_DIR%\lib\libheif.a" (
    echo Converting libheif.a to libheif.lib...
    cd /d "%LIBHEIF_DIR%\lib"
    
    REM Extract .o files from .a archive
    mkdir temp_extract 2>nul
    cd temp_extract
    ar x ..\libheif.a 2>nul || (
        echo ERROR: Failed to extract libheif.a
        echo Make sure you have 'ar' tool available (from MinGW or LLVM)
        cd ..\..
        rmdir /s /q temp_extract 2>nul
        goto :use_force_multiple
    )
    
    REM Convert to .lib using llvm-lib
    if exist *.obj (
        %LLVM_LIB% /out:..\libheif.lib *.obj
        if %errorLevel% equ 0 (
            echo SUCCESS: Created libheif.lib
        ) else (
            echo WARNING: llvm-lib conversion failed, trying /FORCE:MULTIPLE approach
            cd ..\..
            rmdir /s /q temp_extract 2>nul
            goto :use_force_multiple
        )
    ) else (
        echo WARNING: No .obj files extracted from libheif.a
    )
    
    cd ..\..
    rmdir /s /q temp_extract 2>nul
) else (
    echo ERROR: libheif.a not found at %LIBHEIF_DIR%\lib\libheif.a
)

REM Convert libde265.a
if exist "%LIBHEIF_DIR%\lib\libde265.a" (
    echo Converting libde265.a to libde265.lib...
    cd /d "%LIBHEIF_DIR%\lib"
    
    mkdir temp_extract 2>nul
    cd temp_extract
    ar x ..\libde265.a 2>nul || (
        echo ERROR: Failed to extract libde265.a
        cd ..\..
        rmdir /s /q temp_extract 2>nul
        goto :use_force_multiple
    )
    
    if exist *.obj (
        %LLVM_LIB% /out:..\libde265.lib *.obj
        if %errorLevel% equ 0 (
            echo SUCCESS: Created libde265.lib
        ) else (
            echo WARNING: llvm-lib conversion failed for libde265
        )
    )
    
    cd ..\..
    rmdir /s /q temp_extract 2>nul
)

echo.
echo Conversion complete!
goto :end

:use_force_multiple
echo.
echo ========================================
echo Using /FORCE:MULTIPLE linker flag instead
echo ========================================
echo.
echo This will allow linking despite COMDAT incompatibilities.
echo The build.rs has been updated to use this flag.
echo.

:end
echo.
pause

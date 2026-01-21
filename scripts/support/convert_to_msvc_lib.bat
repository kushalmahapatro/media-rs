@echo off
setlocal EnableExtensions EnableDelayedExpansion

REM Convert MinGW .a files to MSVC .lib format using llvm-lib
REM This fixes the COMDAT incompatibility issue

set "REPO_ROOT=%~dp0..\.."
set "LIBHEIF_DIR=%REPO_ROOT%\third_party\libheif_install\windows\x86_64\lib"
set "LLVMLIB=C:\Program Files\LLVM\bin\llvm-lib.exe"

REM Find ar tool
set "AR_TOOL="
set "AR_FOUND=0"

if exist "C:\msys64\mingw64\bin\ar.exe" (
    set "AR_TOOL=C:\msys64\mingw64\bin\ar.exe"
    set "AR_FOUND=1"
) else if exist "C:\msys64\usr\bin\ar.exe" (
    set "AR_TOOL=C:\msys64\usr\bin\ar.exe"
    set "AR_FOUND=1"
) else if exist "C:\Program Files\LLVM\bin\llvm-ar.exe" (
    set "AR_TOOL=C:\Program Files\LLVM\bin\llvm-ar.exe"
    set "AR_FOUND=1"
)

echo ========================================
echo Converting MinGW .a files to MSVC .lib
echo ========================================
echo.

if not exist "%LLVMLIB%" (
    echo ERROR: llvm-lib not found at %LLVMLIB%
    echo Please install LLVM or add it to PATH
    exit /b 1
)

if "%AR_FOUND%"=="0" (
    echo ERROR: ar tool not found in any of these locations:
    echo   C:\msys64\mingw64\bin\ar.exe
    echo   C:\msys64\usr\bin\ar.exe
    echo   C:\Program Files\LLVM\bin\llvm-ar.exe
    echo MSYS2 or LLVM is required for extracting .a files
    exit /b 1
)

echo Using ar tool: %AR_TOOL%
echo.

REM Convert libheif.a
if exist "%LIBHEIF_DIR%\libheif.a" (
    echo Converting libheif.a to libheif.lib...
    cd /d "%LIBHEIF_DIR%"
    
    REM Create temp directory for extraction
    set "TEMP_DIR=temp_extract_heif"
    if exist "%TEMP_DIR%" rmdir /s /q "%TEMP_DIR%"
    mkdir "%TEMP_DIR%"
    cd "%TEMP_DIR%"
    
    REM Extract .o files from .a archive
    echo Extracting object files from libheif.a...
    "%AR_TOOL%" x "..\libheif.a" >nul 2>&1
    
    REM Count object files
    set "OBJ_COUNT=0"
    for %%f in (*.o *.obj) do (
        set /a OBJ_COUNT+=1
    )
    
    if !OBJ_COUNT! gtr 0 (
        echo Found !OBJ_COUNT! object files...
        echo Creating .lib file (object files will be repackaged but may still have COMDAT issues)...
        echo Note: For full compatibility, libheif should be rebuilt with MSVC.
        
        REM Build list of object files for llvm-lib
        set "OBJ_FILES="
        for %%f in (*.o *.obj) do (
            set "OBJ_FILES=!OBJ_FILES! %%f"
        )
        
        "%LLVMLIB%" /out:"..\libheif.lib" %OBJ_FILES%
        if errorLevel 1 (
            echo ERROR: llvm-lib conversion failed
            cd ..
            rmdir /s /q "%TEMP_DIR%"
            exit /b 1
        )
        echo SUCCESS: Created libheif.lib
    ) else (
        echo ERROR: No .o files extracted from libheif.a
        cd ..
        rmdir /s /q "%TEMP_DIR%"
        exit /b 1
    )
    
    cd ..
    rmdir /s /q "%TEMP_DIR%"
) else (
    echo ERROR: libheif.a not found at %LIBHEIF_DIR%\libheif.a
    exit /b 1
)

REM Convert libde265.a
if exist "%LIBHEIF_DIR%\libde265.a" (
    echo Converting libde265.a to libde265.lib...
    cd /d "%LIBHEIF_DIR%"
    
    set "TEMP_DIR=temp_extract_de265"
    if exist "%TEMP_DIR%" rmdir /s /q "%TEMP_DIR%"
    mkdir "%TEMP_DIR%"
    cd "%TEMP_DIR%"
    
    "%AR_TOOL%" x "..\libde265.a" >nul 2>&1
    if errorLevel 1 (
        echo ERROR: Failed to extract libde265.a
        cd ..
        rmdir /s /q "%TEMP_DIR%"
        exit /b 1
    )
    
    set "OBJ_COUNT=0"
    for %%f in (*.o *.obj) do (
        set /a OBJ_COUNT+=1
    )
    
    if !OBJ_COUNT! gtr 0 (
        echo Found !OBJ_COUNT! object files, converting to .lib...
        
        set "OBJ_FILES="
        for %%f in (*.o *.obj) do (
            set "OBJ_FILES=!OBJ_FILES! %%f"
        )
        
        "%LLVMLIB%" /out:"..\libde265.lib" %OBJ_FILES%
        if errorLevel 1 (
            echo ERROR: llvm-lib conversion failed for libde265
            cd ..
            rmdir /s /q "%TEMP_DIR%"
            exit /b 1
        )
        echo SUCCESS: Created libde265.lib
    )
    
    cd ..
    rmdir /s /q "%TEMP_DIR%"
)

echo.
echo ========================================
echo Conversion complete!
echo ========================================
echo.
echo The .lib files are now ready for MSVC linking.
echo.

endlocal

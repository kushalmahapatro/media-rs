@echo off
setlocal EnableExtensions EnableDelayedExpansion

REM Monitor MSVC build and automatically build/run Flutter app when ready

set "REPO_ROOT=%~dp0..\.."
set "DE265_LIB=%REPO_ROOT%\third_party\sources\libde265\build_msvc\Release\libde265.lib"
set "HEIF_LIB=%REPO_ROOT%\third_party\sources\libheif-1.20.2\build_msvc\libheif\Release\libheif.lib"
set "INSTALL_DIR=%REPO_ROOT%\third_party\libheif_install\windows\x86_64\lib"

echo ========================================
echo Monitoring MSVC Build Progress
echo ========================================
echo.
echo Waiting for MSVC build to complete...
echo This will check every 30 seconds.
echo.
echo Looking for:
echo   - %DE265_LIB%
echo   - %HEIF_LIB%
echo.

set "CHECK_COUNT=0"
set "MAX_CHECKS=60"

:check_loop
set /a CHECK_COUNT+=1

if exist "%DE265_LIB%" (
    set "DE265_READY=1"
    echo [Check !CHECK_COUNT!] libde265: READY
) else (
    set "DE265_READY=0"
    echo [Check !CHECK_COUNT!] libde265: building...
)

if exist "%HEIF_LIB%" (
    set "HEIF_READY=1"
    echo [Check !CHECK_COUNT!] libheif: READY
) else (
    set "HEIF_READY=0"
    echo [Check !CHECK_COUNT!] libheif: building...
)

if "!DE265_READY!"=="1" if "!HEIF_READY!"=="1" (
    echo.
    echo ========================================
    echo MSVC BUILD COMPLETE!
    echo ========================================
    echo.
    echo Installing MSVC-built libraries...
    copy /Y "%REPO_ROOT%\third_party\sources\libde265\build_msvc\Release\libde265.lib" "%INSTALL_DIR%\libde265.lib"
    copy /Y "%REPO_ROOT%\third_party\sources\libde265\build_msvc\Release\libde265.lib" "%INSTALL_DIR%\de265.lib"
    copy /Y "%REPO_ROOT%\third_party\sources\libheif-1.20.2\build_msvc\libheif\Release\libheif.lib" "%INSTALL_DIR%\libheif.lib"
    copy /Y "%REPO_ROOT%\third_party\sources\libheif-1.20.2\build_msvc\libheif\Release\libheif.lib" "%INSTALL_DIR%\heif.lib"
    echo Libraries installed!
    echo.
    echo Building Flutter app...
    cd /d "%REPO_ROOT%\example"
    flutter clean
    flutter build windows
    if errorLevel 1 (
        echo.
        echo ERROR: Flutter build failed. Check errors above.
        exit /b 1
    )
    if exist "build\windows\x64\runner\Release\example.exe" (
        echo.
        echo ========================================
        echo SUCCESS: Flutter Windows build completed!
        echo ========================================
        echo.
        echo Launching Flutter app on Windows...
        echo.
        flutter run -d windows
        exit /b 0
    ) else (
        echo.
        echo ERROR: Flutter build completed but executable not found.
        exit /b 1
    )
)

if !CHECK_COUNT! geq !MAX_CHECKS! (
    echo.
    echo ========================================
    echo Timeout: Build taking longer than expected
    echo ========================================
    echo.
    echo Checked !MAX_CHECKS! times (30 minutes).
    echo Please check the build status manually.
    exit /b 1
)

timeout /t 30 /nobreak >nul
goto check_loop

endlocal

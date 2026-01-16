@echo off
echo ========================================
echo PlugPortMon Installation Script
echo ========================================
echo.

REM Check administrator privileges
net session >nul 2>&1
if %errorLevel% neq 0 (
    echo ERROR: This script requires administrator privileges.
    echo Please right-click and select "Run as administrator"
    echo.
    pause
    exit /b 1
)

REM Set paths
set DLL_SOURCE=%~dp0native\PlugPortMon\build\Release\PlugPortMon.dll
set DLL_DEST=C:\Windows\System32\PlugPortMon.dll

REM Check if DLL exists
if not exist "%DLL_SOURCE%" (
    echo ERROR: DLL not found at:
    echo   %DLL_SOURCE%
    echo.
    echo Please build the DLL first using CMake:
    echo   cd native\PlugPortMon
    echo   mkdir build ^&^& cd build
    echo   cmake .. -G "Visual Studio 17 2022" -A x64
    echo   cmake --build . --config Release
    echo.
    pause
    exit /b 1
)

echo [1/4] Copying DLL to Windows system directory...
copy "%DLL_SOURCE%" "%DLL_DEST%" /Y
if %errorLevel% neq 0 (
    echo ERROR: Failed to copy DLL
    pause
    exit /b 1
)
echo DLL copied successfully!

echo.
echo [2/4] Registering monitor in Windows Registry...
reg add "HKLM\SYSTEM\CurrentControlSet\Control\Print\Monitors\PlugPortMon" /v "Driver" /d "PlugPortMon.dll" /f >nul 2>&1
if %errorLevel% neq 0 (
    echo ERROR: Failed to register in registry
    pause
    exit /b 1
)
echo Monitor registered successfully!

echo.
echo [3/4] Restarting Print Spooler...
net stop spooler >nul 2>&1
if %errorLevel% neq 0 (
    echo WARNING: Failed to stop spooler (may already be stopped)
)
net start spooler >nul 2>&1
if %errorLevel% neq 0 (
    echo ERROR: Failed to start spooler
    pause
    exit /b 1
)
echo Print Spooler restarted successfully!

echo.
echo [4/4] Verifying installation...
reg query "HKLM\SYSTEM\CurrentControlSet\Control\Print\Monitors\PlugPortMon" >nul 2>&1
if %errorLevel% neq 0 (
    echo ERROR: Installation verification failed
    pause
    exit /b 1
)
if not exist "%DLL_DEST%" (
    echo ERROR: DLL not found in system directory
    pause
    exit /b 1
)

echo.
echo ========================================
echo Installation completed successfully!
echo ========================================
echo.
echo Next steps to create the printer:
echo 1. Open Windows Settings (Win+I)
echo 2. Go to "Bluetooth ^& devices" ^> "Printers ^& scanners"
echo 3. Click "Add device"
echo 4. Wait, then click "The printer that I want isn't listed"
echo 5. Select "Add a local printer or network printer with manual settings"
echo 6. Click "Next"
echo 7. Select "Create a new port" and choose "PlugPortMon"
echo 8. Enter port name: PLUG001:
echo 9. Click "OK"
echo 10. Select "Generic" manufacturer and "Generic / Text Only" printer
echo 11. Name the printer: "PlugAgent Port Monitor"
echo 12. Complete the wizard
echo.
echo After setup, start the Flutter app and navigate to Port Monitor page.
echo.
pause

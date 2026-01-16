@echo off
echo ========================================
echo PlugPortMon Uninstallation Script
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

echo [1/3] Checking for printers using PlugPortMon...
REM Note: Users should manually delete printers before uninstalling

echo.
echo [2/3] Stopping Print Spooler...
net stop spooler >nul 2>&1
if %errorLevel% neq 0 (
    echo WARNING: Failed to stop spooler (may already be stopped)
)

echo.
echo [3/3] Removing PlugPortMon from system...
if exist "C:\Windows\System32\PlugPortMon.dll" (
    del "C:\Windows\System32\PlugPortMon.dll"
    echo DLL removed from system directory.
) else (
    echo DLL not found in system directory (already removed?).
)

reg delete "HKLM\SYSTEM\CurrentControlSet\Control\Print\Monitors\PlugPortMon" /f >nul 2>&1
if %errorLevel% equ 0 (
    echo Registry entry removed successfully.
) else (
    echo Registry entry not found (already removed?).
)

echo.
echo Starting Print Spooler...
net start spooler >nul 2>&1
if %errorLevel% neq 0 (
    echo ERROR: Failed to start spooler
    pause
    exit /b 1
)

echo.
echo ========================================
echo Uninstallation completed!
echo ========================================
echo.
pause

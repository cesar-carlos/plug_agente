@echo off
REM Runs the unit/integration suite without live ODBC/API tests (--exclude-tags=live).
cd /d "%~dp0\.."
flutter test --exclude-tags=live %*

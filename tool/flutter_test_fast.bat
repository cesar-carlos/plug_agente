@echo off
REM Runs the suite excluding @Tags(['live']) tests (see dart_test.yaml).
flutter test --exclude-tags=live %*

#!/usr/bin/env sh
# Runs only @Tags(['live']) tests (see dart_test.yaml).
set -eu
flutter test --tags=live "$@"

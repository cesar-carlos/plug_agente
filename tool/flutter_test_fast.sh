#!/usr/bin/env sh
# Runs the suite excluding @Tags(['live']) tests (see dart_test.yaml).
set -eu
flutter test --exclude-tags=live "$@"

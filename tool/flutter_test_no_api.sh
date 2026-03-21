#!/usr/bin/env bash
# Runs the unit/integration suite without live ODBC/API tests (--exclude-tags=live).
set -euo pipefail
cd "$(dirname "$0")/.."
exec flutter test --exclude-tags=live "$@"

#!/usr/bin/env bash
# Coverage for RPC + ODBC sources (multi_result hot paths). Writes coverage/lcov_multi_result.info
set -euo pipefail
cd "$(dirname "$0")/.."
flutter test --coverage --exclude-tags=live "$@"
dart run tool/filter_lcov_info.dart coverage/lcov.info coverage/lcov_multi_result.info lib/application/rpc/ lib/infrastructure/external_services/odbc_

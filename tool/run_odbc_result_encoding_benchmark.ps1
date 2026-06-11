# Homolog benchmark gate for ODBC_RESULT_ENCODING (rowMajor vs columnarCompressed).
# Does not change production defaults — set ODBC_RESULT_ENCODING in .env for the run only.
$ErrorActionPreference = 'Stop'
Set-Location (Split-Path $PSScriptRoot -Parent)

Write-Host '== ODBC fast runtime (columnar exports) ==' -ForegroundColor Cyan
dart run tool/check_odbc_fast_runtime.dart --require-columnar-compressed
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Write-Host '== Result encoding contract tests ==' -ForegroundColor Cyan
$paths = Get-Content (Join-Path $PSScriptRoot 'odbc_result_encoding_benchmark_test_paths.txt') |
    Where-Object { $_ -and -not $_.StartsWith('#') }
flutter test @paths
exit $LASTEXITCODE

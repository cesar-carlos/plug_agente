# Verifies that --autostart constant is consistent across:
# - constants/autostart_arg.txt
# - lib/core/constants/app_strings.dart
# - windows/runner/launch_args_constants.h
# - installer/constants.iss
# Exit 0 if all match, 1 otherwise.

$ErrorActionPreference = "Stop"
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$rootDir = Split-Path -Parent $scriptDir
$canonicalPath = Join-Path $rootDir "constants/autostart_arg.txt"
$appStringsPath = Join-Path $rootDir "lib/core/constants/app_strings.dart"
$headerPath = Join-Path $rootDir "windows/runner/launch_args_constants.h"
$constantsIssPath = Join-Path $rootDir "installer/constants.iss"

$canonical = (Get-Content $canonicalPath -Raw).Trim()
if (-not $canonical) {
  Write-Error "constants/autostart_arg.txt is empty"
  exit 1
}

$fail = $false

$appStrings = Get-Content $appStringsPath -Raw
if ($appStrings -notmatch "singleInstanceArgAutostart = '$canonical'") {
  Write-Host "MISMATCH: app_strings.dart does not contain singleInstanceArgAutostart = '$canonical'"
  $fail = $true
}

$header = Get-Content $headerPath -Raw
if ($header -notmatch "kAutostartArg\[\] = `"$canonical`"") {
  Write-Host "MISMATCH: launch_args_constants.h does not contain kAutostartArg = `"$canonical`""
  $fail = $true
}

$constantsIss = Get-Content $constantsIssPath -Raw
if ($constantsIss -notmatch [regex]::Escape($canonical)) {
  Write-Host "MISMATCH: installer/constants.iss does not contain $canonical"
  $fail = $true
}

if ($fail) {
  Write-Host "Run this script from repo root. Canonical value: $canonical"
  exit 1
}

Write-Host "OK: All files use autostart constant: $canonical"
exit 0

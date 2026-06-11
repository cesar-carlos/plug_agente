# Release ritual: analyze + architecture + CI tests + pre_publish dry gate.
param(
    [string]$Version = '',
    [string]$BuildNumber = '1',
    [switch]$AllowDirty
)

$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
Set-Location $root

if (-not $Version) {
    $pubspec = Get-Content 'pubspec.yaml' -Raw
    if ($pubspec -match 'version:\s*(\d+\.\d+\.\d+)') {
        $Version = $Matches[1]
    } else {
        throw 'Could not parse version from pubspec.yaml; pass -Version explicitly.'
    }
}

Write-Host "== flutter analyze ==" -ForegroundColor Cyan
flutter analyze
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Write-Host "== architecture tests ==" -ForegroundColor Cyan
flutter test test/architecture/
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Write-Host "== unit/integration (exclude live/slow/perf) ==" -ForegroundColor Cyan
flutter test --exclude-tags "live || slow || perf"
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Write-Host "== pre_publish_release dry gate ==" -ForegroundColor Cyan
$args = @('tool/pre_publish_release.py', '--version', $Version, '--build-number', $BuildNumber)
if ($AllowDirty) { $args += '--allow-dirty' }
python @args
exit $LASTEXITCODE

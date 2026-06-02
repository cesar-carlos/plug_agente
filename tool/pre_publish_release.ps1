#Requires -Version 5.1
<#
.SYNOPSIS
  Local gate before triggering Publish Windows Release on GitHub Actions.

.DESCRIPTION
  Runs the same analyze/tests subset used by the publish workflow, validates
  version sync and tag availability, then prints gh commands for dry_run and
  production publish (including signing/appcast warnings).

.EXAMPLE
  .\tool\pre_publish_release.ps1 -Version 1.8.4

.EXAMPLE
  .\tool\pre_publish_release.ps1 -Version 1.8.4 -BuildNumber 2 -AllowDirty
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)]
  [string] $Version,

  [string] $BuildNumber = '1',

  [switch] $AllowDirty,

  [switch] $SkipGate
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path $PSScriptRoot -Parent
Push-Location $repoRoot
try {
  if (-not $SkipGate) {
    Write-Host 'Running publish gate (analyze + CI tests + architecture + appcast tooling)...' -ForegroundColor Cyan
    $preflightArgs = @(
      'tool/release_preflight.py',
      '--version', $Version,
      '--gate',
      '--check-secrets',
      '--print-publish-hints',
      '--build-number', $BuildNumber
    )
    if ($AllowDirty) {
      $preflightArgs += '--allow-dirty'
    }
    python @preflightArgs
    if ($LASTEXITCODE -ne 0) {
      throw "Release preflight failed with exit code $LASTEXITCODE."
    }
  }
  else {
    Write-Warning 'Skipped --gate checks (-SkipGate).'
  }

  Write-Host ''
  Write-Host 'Next steps:' -ForegroundColor Green
  Write-Host '  A) Validate installer build without publishing: use dry_run=true in Publish Windows Release.'
  Write-Host '  B) Or run Release Preflight workflow in Actions for a full Windows build on CI.'
  Write-Host '  C) When ready, use the gh command printed above for production publish.'
  Write-Host '  D) Optional: .\tool\install_git_hooks.ps1 (pre-push gate on main for lib/test changes).'
}
finally {
  Pop-Location
}

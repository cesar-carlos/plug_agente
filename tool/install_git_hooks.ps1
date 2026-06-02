#Requires -Version 5.1
<#
.SYNOPSIS
  Installs optional repository git hooks (pre-push release gate).

.EXAMPLE
  .\tool\install_git_hooks.ps1
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path $PSScriptRoot -Parent
$hooksPath = Join-Path $repoRoot 'tool\githooks'

Push-Location $repoRoot
try {
  git config core.hooksPath 'tool/githooks'
  Write-Host "Installed git hooks from $hooksPath" -ForegroundColor Green
  Write-Host 'Pre-push runs release_preflight --gate when pushing main with pubspec/lib/test changes.'
  Write-Host 'Skip once: $env:SKIP_RELEASE_GATE = ''1'''
  Write-Host 'Uninstall: git config --unset core.hooksPath'
}
finally {
  Pop-Location
}

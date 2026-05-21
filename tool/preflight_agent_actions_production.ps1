<#
.SYNOPSIS
  Production-readiness preflight for agent actions (static + optional contract gate).

.DESCRIPTION
  Runs static checks (COM handlers, live .env consistency) then optionally invokes
  homologate_hub_agent_actions.ps1 for contract/UI tests or live Hub validation.

.EXAMPLE
  .\tool\preflight_agent_actions_production.ps1

.EXAMPLE
  .\tool\preflight_agent_actions_production.ps1 -RunContractTests

.EXAMPLE
  .\tool\preflight_agent_actions_production.ps1 -StrictCom -RunContractTests -ValidateLiveEnv
#>
param(
  [switch]$RunContractTests,
  [switch]$ValidateLiveEnv,
  [switch]$PrepareLiveEnv,
  [switch]$RunLiveTests,
  [switch]$StrictCom
)

$ErrorActionPreference = "Stop"

function Write-Step([string]$Message) {
  Write-Host ""
  Write-Host "==> $Message" -ForegroundColor Cyan
}

function Write-Pass([string]$Message) {
  Write-Host "  [ok] $Message" -ForegroundColor Green
}

function Write-Fail([string]$Message) {
  Write-Host "  [fail] $Message" -ForegroundColor Red
}

$repoRoot = Split-Path -Parent $PSScriptRoot
Push-Location $repoRoot
try {
  Write-Step "Agent actions production preflight (static)"
  $dartArgs = @("run", "tool/preflight_agent_actions_production.dart")
  if ($StrictCom) {
    $dartArgs += "--strict-com"
  }
  dart @dartArgs
  if ($LASTEXITCODE -ne 0) {
    Write-Fail "preflight_agent_actions_production.dart reported failures."
    exit $LASTEXITCODE
  }
  Write-Pass "Static production preflight passed."

  $homologateParams = @{}
  if ($RunContractTests) { $homologateParams['RunContractTests'] = $true }
  if ($ValidateLiveEnv) { $homologateParams['ValidateLiveEnv'] = $true }
  if ($PrepareLiveEnv) { $homologateParams['PrepareLiveEnv'] = $true }
  if ($RunLiveTests) { $homologateParams['RunLiveTests'] = $true }

  if ($homologateParams.Count -gt 0) {
    Write-Step "Homologation gate"
    & "$PSScriptRoot/homologate_hub_agent_actions.ps1" @homologateParams
    if ($LASTEXITCODE -ne 0) {
      Write-Fail "homologate_hub_agent_actions.ps1 failed."
      exit $LASTEXITCODE
    }
    Write-Pass "Homologation gate passed."
  } else {
    Write-Host "  [hint] Add -RunContractTests and/or -ValidateLiveEnv for deeper checks." -ForegroundColor DarkGray
  }

  Write-Pass "Production preflight finished."
}
finally {
  Pop-Location
}

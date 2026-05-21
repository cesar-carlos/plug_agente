<#
.SYNOPSIS
  Local/CI operational gate for agent actions (plan: Roteiro operacional pos-MVP steps 1-2).

.DESCRIPTION
  Runs production preflight and the full contract/UI homologation bundle.
  Prints reminders for human security checklist (step 3) and live Hub (steps 4-6).

.EXAMPLE
  .\tool\run_agent_actions_operational_gate.ps1

.EXAMPLE
  .\tool\run_agent_actions_operational_gate.ps1 -StrictCom
#>
param(
  [switch]$StrictCom
)

$ErrorActionPreference = "Stop"

$preflightParams = @{
  RunContractTests = $true
}
if ($StrictCom) {
  $preflightParams['StrictCom'] = $true
}

& "$PSScriptRoot/preflight_agent_actions_production.ps1" @preflightParams
if ($LASTEXITCODE -ne 0) {
  exit $LASTEXITCODE
}

Write-Host ""
Write-Host "Operational gate (local/CI) passed." -ForegroundColor Green
Write-Host "Next steps (see plano - Roteiro operacional pos-MVP):" -ForegroundColor Cyan
Write-Host "  3. dart run tool/agent_action_security_gate_checklist.dart [tipo]"
Write-Host "  4-6. .\tool\homologate_hub_agent_actions.ps1 -PrepareLiveEnv -ValidateLiveEnv -RunLiveTests"
Write-Host "  7. COM handlers in com_object_production_registrations.dart (or RA-01)"
Write-Host "  8. Hub allowlist/rate limit (cross-repo, RA-02)"

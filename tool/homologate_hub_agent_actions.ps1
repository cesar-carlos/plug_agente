<#
.SYNOPSIS
  Pre-flight checks for Hub agent.action.* homologation (MVP 3 / pos-roteamento).

.DESCRIPTION
  Validates .env for live hub agent.action tests, optionally runs contract/unit tests,
  and runs opt-in Socket.IO live tests when flags are set.

.EXAMPLE
  .\tool\homologate_hub_agent_actions.ps1

.EXAMPLE
  .\tool\homologate_hub_agent_actions.ps1 -RunContractTests -RunLiveTests
#>
param(
  [switch]$RunContractTests,
  [switch]$RunLiveTests,
  [switch]$ValidateLiveEnv,
  [switch]$PrepareLiveEnv
)

$ErrorActionPreference = "Stop"

function Write-Step([string]$Message) {
  Write-Host ""
  Write-Host "==> $Message" -ForegroundColor Cyan
}

function Write-Pass([string]$Message) {
  Write-Host "  [ok] $Message" -ForegroundColor Green
}

function Write-Warn([string]$Message) {
  Write-Host "  [warn] $Message" -ForegroundColor Yellow
}

function Write-Fail([string]$Message) {
  Write-Host "  [fail] $Message" -ForegroundColor Red
}

function Get-ManifestTestPaths([string]$FileName) {
  $manifestPath = Join-Path $PSScriptRoot $FileName
  if (-not (Test-Path $manifestPath)) {
    throw "Missing test manifest: $manifestPath"
  }
  Get-Content -Path $manifestPath |
    ForEach-Object { $_.Trim() } |
    Where-Object { $_ -and -not $_.StartsWith('#') }
}

$repoRoot = Split-Path -Parent $PSScriptRoot
Push-Location $repoRoot
try {
  Write-Step "E2E environment"
  dart run tool/check_e2e_env.dart
  if ($LASTEXITCODE -ne 0) {
    Write-Fail "check_e2e_env.dart failed."
    exit $LASTEXITCODE
  }
  Write-Pass "check_e2e_env.dart completed."

  if ($PrepareLiveEnv) {
    Write-Step "Prepare live Hub .env from local app storage"
    dart run tool/sync_e2e_hub_env_from_local.dart --export-secure
    if ($LASTEXITCODE -ne 0) {
      Write-Warn "sync_e2e_hub_env_from_local.dart finished with missing variables (see hints above)."
    } else {
      Write-Pass "sync_e2e_hub_env_from_local.dart completed."
    }
    Write-Step "Promote signing from plug_server/.env (monorepo)"
    dart run tool/promote_e2e_signing_from_monorepo_env.dart --force
    if ($LASTEXITCODE -ne 0) {
      Write-Step "Generate dev signing pair (agent + sibling plug_server/.env)"
      dart run tool/generate_dev_e2e_signing.dart --write
      if ($LASTEXITCODE -ne 0) {
        Write-Warn "generate_dev_e2e_signing.dart failed."
      }
    } else {
      Write-Pass "Signing keys promoted from monorepo."
    }
    Write-Step "Refresh E2E_HUB_TOKEN (local DB, saved credentials, or E2E_HUB_USERNAME/PASSWORD)"
    dart run tool/fetch_e2e_hub_token_from_local_config.dart --apply-token --force
    if ($LASTEXITCODE -ne 0) {
      Write-Warn "Token refresh skipped - sign in via Config or set E2E_HUB_TOKEN / E2E_HUB_USERNAME in .env."
    } else {
      Write-Pass "E2E_HUB_TOKEN refresh attempted."
    }
  }

  if ($ValidateLiveEnv) {
    Write-Step "Live Hub agent.action preflight"
    dart run tool/validate_live_hub_agent_actions_env.dart
    if ($LASTEXITCODE -ne 0) {
      Write-Fail "validate_live_hub_agent_actions_env.dart failed."
      exit $LASTEXITCODE
    }
    Write-Pass "Live Hub variables present (run -RunLiveTests to execute hub_agent_action_rpc_live_e2e_test.dart)."
  }

  if ($RunContractTests) {
    Write-Step "Agent actions production preflight (static)"
    dart run tool/preflight_agent_actions_production.dart
    if ($LASTEXITCODE -ne 0) {
      Write-Fail "Production preflight failed."
      exit $LASTEXITCODE
    }
    Write-Pass "Production preflight passed."

    Write-Step "Agent action contract tests (local)"
    $contractPaths = @(Get-ManifestTestPaths 'agent_actions_contract_test_paths.txt')
    flutter test @contractPaths
    if ($LASTEXITCODE -ne 0) {
      Write-Fail "Contract tests failed."
      exit $LASTEXITCODE
    }
    Write-Pass "Contract tests passed."

    Write-Step "Agent actions UI regression (local)"
    $uiPaths = @(Get-ManifestTestPaths 'agent_actions_ui_test_paths.txt')
    flutter test @uiPaths
    if ($LASTEXITCODE -ne 0) {
      Write-Fail "UI regression tests failed."
      exit $LASTEXITCODE
    }
    Write-Pass "UI regression tests passed."
  } else {
    Write-Warn "Skipped contract tests (use -RunContractTests)."
  }

  if ($RunLiveTests) {
    Write-Step "Hub Socket smoke (connect)"
    flutter test test/integration/hub_socket_live_e2e_test.dart --name "should connect"
    if ($LASTEXITCODE -ne 0) {
      Write-Fail @'
Hub Socket connect smoke failed (check E2E_HUB_URL and E2E_HUB_TOKEN).
If the error mentions jwt expired, refresh the token:
  dart run tool/fetch_e2e_hub_token_from_local_config.dart --apply-token --force
(sign in via Config, E2E_HUB_USERNAME/PASSWORD in .env, or set E2E_HUB_TOKEN from Hub admin).
'@
      exit $LASTEXITCODE
    }
    Write-Pass "Hub Socket connect smoke passed."

    Write-Step "Hub signed capabilities smoke (PAYLOAD_SIGNING_* must match Hub)"
    flutter test test/integration/hub_socket_live_e2e_test.dart --name "signed PayloadFrame"
    if ($LASTEXITCODE -ne 0) {
      Write-Fail @'
Signed capabilities smoke failed. Socket connect succeeded but agent:capabilities did not arrive.
- Use the same PAYLOAD_SIGNING_KEY_ID and PAYLOAD_SIGNING_KEY as the deployed Hub (not e2e-dev on production).
- dart run tool/export_e2e_secrets_from_local.dart
- dart run tool/promote_e2e_signing_from_monorepo_env.dart
- dart run tool/validate_live_hub_agent_actions_env.dart
'@
      exit $LASTEXITCODE
    }
    Write-Pass "Hub signed capabilities smoke passed."

    Write-Step "Hub agent.action live tests (opt-in)"
    flutter test test/integration/hub_agent_action_rpc_live_e2e_test.dart --tags live
    if ($LASTEXITCODE -ne 0) {
      Write-Fail "Live hub agent.action tests failed."
      exit $LASTEXITCODE
    }
    Write-Pass "Live hub agent.action tests passed."
  } else {
    Write-Warn "Skipped live tests (use -RunLiveTests after configuring .env)."
  }

  Write-Step "Manual checklist"
  $manualChecklist = @'
  1. Hub must advertise extensions.agentActions in agent:capabilities (set E2E_HUB_EXPECT_AGENT_ACTIONS_CAPABILITY=true to assert).
  2. For inbound RPC smoke, hub must emit agent.action.* after agent:ready (E2E_HUB_EXPECT_AGENT_ACTION_RPC=true).
  3. Production: enforce allowlist/rate limit on Hub; agent already routes agent.action.run/validateRun/cancel/getExecution.
  4. Register COM handlers in com_object_production_registrations.dart (or AGENT_ACTION_COM_STUB_* for homologation).
  5. Homologation COM stub: AGENT_ACTION_COM_STUB_ENABLED=true plus PROG_ID/MEMBER_NAME in .env (see docs/testing/e2e_setup.md).
  6. Security gate per type: dart run tool/agent_action_security_gate_checklist.dart [type]
'@
  Write-Host $manualChecklist -ForegroundColor Gray
  if ($RunContractTests) {
    dart run tool/agent_action_security_gate_checklist.dart | Out-Host
  }
  Write-Pass "Homologation script finished."
}
finally {
  Pop-Location
}

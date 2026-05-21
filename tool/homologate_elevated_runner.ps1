<#
.SYNOPSIS
  Pre-flight checks for Windows elevated action runner homologation (MVP 4).

.DESCRIPTION
  Builds the helper when needed, verifies artifact paths, optionally runs unit tests,
  and prints the manual UI/UAC checklist. Does not drive UAC or the Flutter UI.

.EXAMPLE
  .\tool\homologate_elevated_runner.ps1 -Build

.EXAMPLE
  .\tool\homologate_elevated_runner.ps1 -Build -RunUnitTests
#>
param(
  [switch]$Build,
  [switch]$RunUnitTests
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

$repoRoot = Split-Path -Parent $PSScriptRoot
$buildScript = Join-Path $repoRoot "tool\build_elevated_runner.ps1"
$buildExe = Join-Path $repoRoot "build\elevated_runner\plug_agente_elevated_runner.exe"
$releaseExe = Join-Path $repoRoot "build\windows\x64\runner\Release\plug_agente_elevated_runner.exe"
$taskName = "PlugAgente\ElevatedActionRunner"

$failed = $false

Write-Step "Platform"
if ($env:OS -ne "Windows_NT") {
  Write-Fail "Elevated runner homologation requires Windows."
  exit 1
}
Write-Pass "Windows detected."

Write-Step "Helper executable"
if ($Build -or -not (Test-Path $buildExe)) {
  if (-not (Test-Path $buildScript)) {
    Write-Fail "Missing build script: $buildScript"
    exit 1
  }
  Write-Host "  Building via $buildScript ..."
  & $buildScript
  if ($LASTEXITCODE -ne 0) {
    Write-Fail "build_elevated_runner.ps1 failed."
    exit $LASTEXITCODE
  }
}

if (Test-Path $buildExe) {
  Write-Pass "Build output: $buildExe"
} else {
  Write-Fail "Helper not found at $buildExe (run with -Build)."
  $failed = $true
}

if (Test-Path $releaseExe) {
  Write-Pass "Bundled next to app runner: $releaseExe"
} else {
  Write-Warn "Release bundle missing: $releaseExe (run flutter build windows or copy helper manually)."
}

$envExe = $env:ELEVATED_ACTION_RUNNER_EXE
if ($envExe) {
  if (Test-Path $envExe) {
    Write-Pass "ELEVATED_ACTION_RUNNER_EXE exists: $envExe"
  } else {
    Write-Fail "ELEVATED_ACTION_RUNNER_EXE points to missing file: $envExe"
    $failed = $true
  }
} else {
  Write-Warn "ELEVATED_ACTION_RUNNER_EXE not set (resolver uses sibling of plug_agente.exe)."
}

Write-Step "Scheduled task (optional until UI Prepare)"
$previousErrorAction = $ErrorActionPreference
$ErrorActionPreference = "Continue"
$taskQuery = & schtasks.exe /Query /TN $taskName /FO LIST 2>&1
$taskExitCode = $LASTEXITCODE
$ErrorActionPreference = $previousErrorAction
if ($taskExitCode -eq 0) {
  Write-Pass "Scheduled task registered: $taskName"
} else {
  Write-Warn "Scheduled task not found yet. Use Actions page -> Prepare elevated runner."
}

if ($RunUnitTests) {
  Write-Step "Unit tests (no UAC)"
  Push-Location $repoRoot
  try {
    flutter test `
      test/infrastructure/actions/elevated_action_runner_installer_test.dart `
      test/application/actions/elevated_agent_action_execution_service_test.dart `
      test/infrastructure/actions/elevated_action_request_protector_test.dart `
      test/presentation/widgets/agent_actions/agent_action_confirmations_test.dart `
      test/presentation/widgets/agent_actions/agent_action_risk_labels_test.dart
    if ($LASTEXITCODE -ne 0) {
      Write-Fail "Elevated-related unit tests failed."
      $failed = $true
    } else {
      Write-Pass "Elevated-related unit tests passed."
    }
  } finally {
    Pop-Location
  }
} else {
  Write-Warn "Skipped unit tests. Re-run with -RunUnitTests for automated gate."
}

Write-Step "Manual homologation (UI + UAC)"
Write-Host @"
  1. flutter run -d windows (or use installed build).
  2. Enable feature flag: Elevated agent actions.
  3. Actions page -> Prepare elevated runner (accept UAC for scheduled task).
  4. Create/edit action -> enable elevated (confirm dialog) -> Test -> Run.
  5. Verify execution succeeds; check diagnostics (no degraded elevated state).
  6. Optional: cancel/kill while running; retry after helper stop.

  Bridge dirs under app data: agent_actions/elevated/{requests,status,cancel,materialized}
  Ready marker: agent_actions/elevated/elevated_runner.ready

  See docs/testing/e2e_setup.md (Elevated action runner section).
"@

if ($failed) {
  Write-Host ""
  Write-Fail "Pre-flight checks failed. Fix issues above before field homologation."
  exit 1
}

Write-Host ""
Write-Pass "Pre-flight checks complete. Continue with manual steps above."

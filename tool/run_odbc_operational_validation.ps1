<#
.SYNOPSIS
  Runs the ODBC operational validation flow and writes a Markdown worksheet.

.DESCRIPTION
  Loads .env into the current process when present, optionally runs the
  preflight/smoke/burst/benchmark steps, and writes a timestamped Markdown
  report under artifacts/odbc_validation/.

.EXAMPLE
  .\tool\run_odbc_operational_validation.ps1

.EXAMPLE
  .\tool\run_odbc_operational_validation.ps1 -All

.EXAMPLE
  .\tool\run_odbc_operational_validation.ps1 -RunSmoke -RunBenchmark
#>
param(
  [switch]$RunSmoke,
  [switch]$RunBurst,
  [switch]$RunBenchmark,
  [switch]$All,
  [switch]$SkipPreflight,
  [string]$EnvPath = ".env",
  [string]$OutputPath
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

function Import-DotEnvIfPresent {
  param([string]$Path)

  if (-not (Test-Path -LiteralPath $Path)) {
    return
  }

  foreach ($line in Get-Content -LiteralPath $Path) {
    $trimmed = $line.Trim()
    if ($trimmed.Length -eq 0 -or $trimmed.StartsWith("#")) {
      continue
    }

    $parts = $trimmed.Split("=", 2)
    if ($parts.Count -ne 2) {
      continue
    }

    $key = $parts[0].Trim()
    $value = $parts[1].Trim()
    if ($key.Length -eq 0) {
      continue
    }

    if ([string]::IsNullOrWhiteSpace([Environment]::GetEnvironmentVariable($key, "Process"))) {
      [Environment]::SetEnvironmentVariable($key, $value, "Process")
    }
  }
}

function Get-EffectiveEnvValue {
  param([string[]]$Keys)

  foreach ($key in $Keys) {
    $value = [Environment]::GetEnvironmentVariable($key, "Process")
    if (-not [string]::IsNullOrWhiteSpace($value)) {
      return $value.Trim()
    }
  }

  return ""
}

function Get-GitCommitOrDefault {
  try {
    $commit = (git rev-parse --short HEAD 2>$null)
    if (-not [string]::IsNullOrWhiteSpace($commit)) {
      return $commit.Trim()
    }
  } catch {
  }

  return "(not resolved)"
}

function Update-ContextFromHealthSnapshotTemplate {
  param(
    [hashtable]$Context,
    [string]$TemplatePath
  )

  if (-not (Test-Path -LiteralPath $TemplatePath)) {
    return
  }

  try {
    $snapshot = Get-Content -LiteralPath $TemplatePath -Raw | ConvertFrom-Json
    if ($null -eq $snapshot) {
      return
    }

    $runtime = $snapshot.odbc_runtime_tuning
    if ($null -ne $runtime) {
      if ($null -ne $runtime.pool_size) {
        $Context.OdbcPoolSize = [string]$runtime.pool_size
      }
      if ($null -ne $runtime.async_worker_count) {
        $Context.OdbcAsyncWorkerCount = [string]$runtime.async_worker_count
      }
      if ($null -ne $runtime.async_max_pending_requests) {
        $Context.OdbcAsyncMaxPendingRequests = [string]$runtime.async_max_pending_requests
      }
    }

    $sqlQueue = $snapshot.sql_queue
    if ($null -ne $sqlQueue) {
      if ($null -ne $sqlQueue.max_size) {
        $Context.SqlQueueMaxSize = [string]$sqlQueue.max_size
      }
      if ($null -ne $sqlQueue.max_workers) {
        $Context.SqlQueueMaxWorkers = [string]$sqlQueue.max_workers
      }
      if ($null -ne $sqlQueue.enqueue_timeout_seconds) {
        $Context.SqlQueueTimeoutSec = [string]$sqlQueue.enqueue_timeout_seconds
      }
    }

    $pool = $snapshot.pool
    if ($null -ne $pool -and $null -ne $pool.acquire_timeout_seconds) {
      $Context.PoolAcquireTimeoutSec = [string]$pool.acquire_timeout_seconds
    }
  } catch {
    Write-Warn "Could not parse health snapshot template for effective tuning."
  }
}

function Get-DefaultOutputPath {
  param([string]$RunDirectory)

  if (-not (Test-Path -LiteralPath $RunDirectory)) {
    New-Item -ItemType Directory -Path $RunDirectory -Force | Out-Null
  }

  return Join-Path $RunDirectory "odbc_operational_validation_report.md"
}

function New-ValidationReport {
  param(
    [hashtable]$Context,
    [hashtable]$Steps
  )

  $reportLines = @(
    '# ODBC Operational Validation Report',
    '',
    ('Generated at: {0}' -f $Context.GeneratedAt),
    '',
    '## Environment',
    '',
    '| Field | Value |',
    '| --- | --- |',
    ('| Operator | {0} |' -f $Context.Operator),
    ('| Host | {0} |' -f $Context.Host),
    ('| Repo root | `{0}` |' -f $Context.RepoRoot),
    ('| Run directory | `{0}` |' -f $Context.RunDirectory),
    ('| Build / commit | `{0}` |' -f $Context.Commit),
    ('| DSN used | `{0}` |' -f $Context.DsnUsed),
    ('| Smoke query | `{0}` |' -f $Context.SmokeQuery),
    ('| Long query | `{0}` |' -f $Context.LongQuery),
    '',
    '## Effective Tuning',
    '',
    '```env',
    ('ODBC_POOL_SIZE={0}' -f $Context.OdbcPoolSize),
    ('ODBC_ASYNC_WORKER_COUNT={0}' -f $Context.OdbcAsyncWorkerCount),
    ('ODBC_ASYNC_MAX_PENDING_REQUESTS={0}' -f $Context.OdbcAsyncMaxPendingRequests),
    ('SQL_QUEUE_MAX_SIZE={0}' -f $Context.SqlQueueMaxSize),
    ('SQL_QUEUE_MAX_WORKERS={0}' -f $Context.SqlQueueMaxWorkers),
    ('SQL_QUEUE_TIMEOUT_SEC={0}' -f $Context.SqlQueueTimeoutSec),
    ('ODBC_POOL_ACQUIRE_TIMEOUT_SEC={0}' -f $Context.PoolAcquireTimeoutSec),
    ('CIRCUIT_BREAKER_FAILURE_THRESHOLD={0}' -f $Context.CircuitBreakerFailureThreshold),
    ('CIRCUIT_BREAKER_RESET_SEC={0}' -f $Context.CircuitBreakerResetSec),
    ('RUN_ODBC_BURST_TESTS={0}' -f $Context.RunOdbcBurstTests),
    '```',
    '',
    '## Step Status',
    '',
    '| Step | Status | Command |',
    '| --- | --- | --- |',
    ('| Preflight | {0} | `{1}` |' -f $Steps.Preflight.Status, $Steps.Preflight.Command),
    ('| Smoke | {0} | `{1}` |' -f $Steps.Smoke.Status, $Steps.Smoke.Command),
    ('| Burst | {0} | `{1}` |' -f $Steps.Burst.Status, $Steps.Burst.Command),
    ('| Benchmark | {0} | `{1}` |' -f $Steps.Benchmark.Status, $Steps.Benchmark.Command),
    '',
    '## Step Artifacts',
    '',
    '| Step | Log | Started at | Finished at |',
    '| --- | --- | --- | --- |',
    ('| Preflight | {0} | {1} | {2} |' -f $Steps.Preflight.Log, $Steps.Preflight.StartedAt, $Steps.Preflight.FinishedAt),
    ('| Smoke | {0} | {1} | {2} |' -f $Steps.Smoke.Log, $Steps.Smoke.StartedAt, $Steps.Smoke.FinishedAt),
    ('| Burst | {0} | {1} | {2} |' -f $Steps.Burst.Log, $Steps.Burst.StartedAt, $Steps.Burst.FinishedAt),
    ('| Benchmark | {0} | {1} | {2} |' -f $Steps.Benchmark.Log, $Steps.Benchmark.StartedAt, $Steps.Benchmark.FinishedAt),
    '',
    '## Auxiliary Artifacts',
    '',
    '| Artifact | Purpose |',
    '| --- | --- |',
    '| `health_snapshot_template.json` | Template no shape atual de `agent.getHealth` com tuning efetivo do ambiente local. |',
    '',
    '## Manual Health Snapshots',
    '',
    'Collect `agent.getHealth` or `HealthService.getHealthStatusAsync()` before and after the burst.',
    '',
    '### Snapshot Before Burst',
    '',
    '```json',
    '{}',
    '```',
    '',
    '### Snapshot After Burst',
    '',
    '```json',
    '{}',
    '```',
    '',
    '## Quick Comparison',
    '',
    '| Field | Before | After | Notes |',
    '| --- | --- | --- | --- |',
    '| `odbc_runtime_tuning.async_worker_count` | | | |',
    '| `odbc_runtime_tuning.async_max_pending_requests` | | | |',
    '| `pool.active_count` | | | |',
    '| `pool.fallbacks_total` | | | |',
    '| `sql_queue.rejections_total` | | | |',
    '| `sql_queue.timeouts_total` | | | |',
    '| `sql_queue.p95_wait_time_ms` | | | |',
    '| `queries.p95_latency_ms` | | | |',
    '| `queries.p99_latency_ms` | | | |',
    '| `timeouts.pool_total` | | | |',
    '',
    '## Notes',
    '',
    '- Tuning decision:',
    '- Risks observed:',
    '- Follow-up:',
    ''
  )

  return ($reportLines -join [Environment]::NewLine)
}

function Invoke-StepCommand {
  param(
    [string]$Name,
    [string]$CommandText,
    [string]$LogPath,
    [scriptblock]$Command
  )

  Write-Step $Name
  $startedAt = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss zzz")
  $null = & $Command *>&1 | Tee-Object -FilePath $LogPath -Append
  $exitCode = $LASTEXITCODE
  $finishedAt = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss zzz")
  if ($exitCode -ne 0) {
    Write-Fail "$Name failed."
    return @{
      Succeeded = $false
      StartedAt = $startedAt
      FinishedAt = $finishedAt
    }
  }

  Write-Pass "$Name completed."
  return @{
    Succeeded = $true
    StartedAt = $startedAt
    FinishedAt = $finishedAt
  }
}

if ($All) {
  $RunSmoke = $true
  $RunBurst = $true
  $RunBenchmark = $true
}

$repoRoot = Split-Path -Parent $PSScriptRoot
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$runDirectory = Join-Path $repoRoot "artifacts\odbc_validation\$timestamp"
$resolvedEnvPath = if ([System.IO.Path]::IsPathRooted($EnvPath)) {
  $EnvPath
} else {
  Join-Path $repoRoot $EnvPath
}

Import-DotEnvIfPresent -Path $resolvedEnvPath

$context = @{
  GeneratedAt = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss zzz")
  Operator = if ($env:USERNAME) { $env:USERNAME } else { "(unknown)" }
  Host = if ($env:COMPUTERNAME) { $env:COMPUTERNAME } else { "(unknown)" }
  RepoRoot = $repoRoot
  RunDirectory = $runDirectory
  Commit = Get-GitCommitOrDefault
  DsnUsed = Get-EffectiveEnvValue @("ODBC_E2E_RPC_DSN", "ODBC_TEST_DSN", "ODBC_DSN", "ODBC_TEST_DSN_SQL_SERVER", "ODBC_DSN_SQL_SERVER", "ODBC_TEST_DSN_POSTGRESQL", "ODBC_DSN_POSTGRESQL")
  SmokeQuery = Get-EffectiveEnvValue @("ODBC_INTEGRATION_SMOKE_QUERY")
  LongQuery = Get-EffectiveEnvValue @("ODBC_INTEGRATION_LONG_QUERY", "ODBC_INTEGRATION_LONG_QUERY_SQL_ANYWHERE", "ODBC_INTEGRATION_LONG_QUERY_SQL_SERVER", "ODBC_INTEGRATION_LONG_QUERY_POSTGRESQL")
  OdbcPoolSize = Get-EffectiveEnvValue @("ODBC_POOL_SIZE")
  OdbcAsyncWorkerCount = Get-EffectiveEnvValue @("ODBC_ASYNC_WORKER_COUNT")
  OdbcAsyncMaxPendingRequests = Get-EffectiveEnvValue @("ODBC_ASYNC_MAX_PENDING_REQUESTS")
  SqlQueueMaxSize = Get-EffectiveEnvValue @("SQL_QUEUE_MAX_SIZE")
  SqlQueueMaxWorkers = Get-EffectiveEnvValue @("SQL_QUEUE_MAX_WORKERS")
  SqlQueueTimeoutSec = Get-EffectiveEnvValue @("SQL_QUEUE_TIMEOUT_SEC")
  PoolAcquireTimeoutSec = Get-EffectiveEnvValue @("ODBC_POOL_ACQUIRE_TIMEOUT_SEC")
  CircuitBreakerFailureThreshold = Get-EffectiveEnvValue @("CIRCUIT_BREAKER_FAILURE_THRESHOLD")
  CircuitBreakerResetSec = Get-EffectiveEnvValue @("CIRCUIT_BREAKER_RESET_SEC")
  RunOdbcBurstTests = Get-EffectiveEnvValue @("RUN_ODBC_BURST_TESTS")
}

if ([string]::IsNullOrWhiteSpace($context.SmokeQuery)) {
  $context.SmokeQuery = "SELECT 1"
}

if ([string]::IsNullOrWhiteSpace($context.DsnUsed)) {
  $context.DsnUsed = "(not configured)"
}

if ([string]::IsNullOrWhiteSpace($context.LongQuery)) {
  $context.LongQuery = "(not configured)"
}

if ([string]::IsNullOrWhiteSpace($context.CircuitBreakerFailureThreshold)) {
  $context.CircuitBreakerFailureThreshold = "5"
}

if ([string]::IsNullOrWhiteSpace($context.CircuitBreakerResetSec)) {
  $context.CircuitBreakerResetSec = "30"
}

$steps = @{
  Preflight = @{
    Status = if ($SkipPreflight) { "skipped" } else { "pending" }
    Command = "dart run tool/check_e2e_env.dart"
    Log = if ($SkipPreflight) { "(not requested)" } else { "preflight.log" }
    StartedAt = "-"
    FinishedAt = "-"
  }
  Smoke = @{
    Status = if ($RunSmoke) { "pending" } else { "not requested" }
    Command = "flutter test test/integration/odbc_queued_gateway_smoke_live_e2e_test.dart"
    Log = if ($RunSmoke) { "smoke.log" } else { "(not requested)" }
    StartedAt = "-"
    FinishedAt = "-"
  }
  Burst = @{
    Status = if ($RunBurst) { "pending" } else { "not requested" }
    Command = "flutter test test/integration/sql_queue_burst_test.dart"
    Log = if ($RunBurst) { "burst.log" } else { "(not requested)" }
    StartedAt = "-"
    FinishedAt = "-"
  }
  Benchmark = @{
    Status = if ($RunBenchmark) { "pending" } else { "not requested" }
    Command = ".\tool\odbc_async_benchmark.ps1"
    Log = if ($RunBenchmark) { "benchmark.log" } else { "(not requested)" }
    StartedAt = "-"
    FinishedAt = "-"
  }
}

$reportPath = if ([string]::IsNullOrWhiteSpace($OutputPath)) {
  Get-DefaultOutputPath -RunDirectory $runDirectory
} elseif ([System.IO.Path]::IsPathRooted($OutputPath)) {
  $outputDir = Split-Path -Parent $OutputPath
  if ($outputDir -and -not (Test-Path -LiteralPath $outputDir)) {
    New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
  }
  $OutputPath
} else {
  $resolvedOutput = Join-Path $repoRoot $OutputPath
  $outputDir = Split-Path -Parent $resolvedOutput
  if ($outputDir -and -not (Test-Path -LiteralPath $outputDir)) {
    New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
  }
  $resolvedOutput
}

$failureDetected = $false
if (-not (Test-Path -LiteralPath $runDirectory)) {
  New-Item -ItemType Directory -Path $runDirectory -Force | Out-Null
}

$healthSnapshotTemplatePath = Join-Path $runDirectory 'health_snapshot_template.json'

Push-Location $repoRoot
try {
  Write-Step "Health snapshot template"
  dart run tool/export_odbc_health_snapshot_template.dart --output $healthSnapshotTemplatePath
  if ($LASTEXITCODE -ne 0) {
    Write-Warn "Health snapshot template generation failed."
  } else {
    Update-ContextFromHealthSnapshotTemplate -Context $context -TemplatePath $healthSnapshotTemplatePath
    Write-Pass "Health snapshot template generated."
  }

  if (-not $SkipPreflight) {
    $preflightResult = Invoke-StepCommand -Name "Preflight" -CommandText $steps.Preflight.Command -LogPath (Join-Path $runDirectory $steps.Preflight.Log) -Command {
      dart run tool/check_e2e_env.dart
    }
    $steps.Preflight.Status = if ($preflightResult.Succeeded) { "passed" } else { "failed" }
    $steps.Preflight.StartedAt = $preflightResult.StartedAt
    $steps.Preflight.FinishedAt = $preflightResult.FinishedAt
    if (-not $preflightResult.Succeeded) {
      $failureDetected = $true
      throw "Preflight failed."
    }
  }

  if ($RunSmoke) {
    $smokeResult = Invoke-StepCommand -Name "Smoke" -CommandText $steps.Smoke.Command -LogPath (Join-Path $runDirectory $steps.Smoke.Log) -Command {
      flutter test test/integration/odbc_queued_gateway_smoke_live_e2e_test.dart
    }
    $steps.Smoke.Status = if ($smokeResult.Succeeded) { "passed" } else { "failed" }
    $steps.Smoke.StartedAt = $smokeResult.StartedAt
    $steps.Smoke.FinishedAt = $smokeResult.FinishedAt
    if (-not $smokeResult.Succeeded) {
      $failureDetected = $true
      throw "Smoke failed."
    }
  }

  if ($RunBurst) {
    $env:RUN_ODBC_BURST_TESTS = "true"
    $context.RunOdbcBurstTests = "true"
    $burstResult = Invoke-StepCommand -Name "Burst" -CommandText $steps.Burst.Command -LogPath (Join-Path $runDirectory $steps.Burst.Log) -Command {
      flutter test test/integration/sql_queue_burst_test.dart
    }
    $steps.Burst.Status = if ($burstResult.Succeeded) { "passed" } else { "failed" }
    $steps.Burst.StartedAt = $burstResult.StartedAt
    $steps.Burst.FinishedAt = $burstResult.FinishedAt
    if (-not $burstResult.Succeeded) {
      $failureDetected = $true
      throw "Burst failed."
    }
  }

  if ($RunBenchmark) {
    $benchmarkResult = Invoke-StepCommand -Name "Benchmark" -CommandText $steps.Benchmark.Command -LogPath (Join-Path $runDirectory $steps.Benchmark.Log) -Command {
      & (Join-Path $repoRoot "tool\odbc_async_benchmark.ps1")
    }
    $steps.Benchmark.Status = if ($benchmarkResult.Succeeded) { "passed" } else { "failed" }
    $steps.Benchmark.StartedAt = $benchmarkResult.StartedAt
    $steps.Benchmark.FinishedAt = $benchmarkResult.FinishedAt
    if (-not $benchmarkResult.Succeeded) {
      $failureDetected = $true
      throw "Benchmark failed."
    }
  }
}
finally {
  $report = New-ValidationReport -Context $context -Steps $steps
  Set-Content -LiteralPath $reportPath -Value $report -Encoding UTF8
  Write-Host ""
  Write-Host "Validation worksheet: $reportPath" -ForegroundColor Gray
  Write-Host "Run artifacts directory: $runDirectory" -ForegroundColor Gray
  Write-Host "Fill the health snapshots manually from agent.getHealth or HealthService.getHealthStatusAsync()." -ForegroundColor Gray
  Pop-Location
}

if ($failureDetected) {
  exit 1
}

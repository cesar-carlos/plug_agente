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
  .\tool\run_odbc_operational_validation.ps1 -RunSmoke -RunBenchmark -RunStreamingBenchmark -RunDriverMatrixBenchmark
#>
param(
  [switch]$RunSmoke,
  [switch]$RunBurst,
  [switch]$RunBenchmark,
  [switch]$RunStreamingBenchmark,
  [switch]$RunDriverMatrixBenchmark,
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

function Get-DsnDriverFamily {
  param([string]$ConnectionString)

  if ([string]::IsNullOrWhiteSpace($ConnectionString) -or $ConnectionString -eq "(not configured)") {
    return "(not configured)"
  }

  $upper = $ConnectionString.ToUpperInvariant()
  if ($upper.Contains("POSTGRE")) {
    return "PostgreSQL"
  }
  if ($upper.Contains("ANYWHERE") -or $upper.Contains("SYBASE") -or $upper.Contains("SQLA")) {
    return "SQL Anywhere"
  }
  if ($upper.Contains("SQL SERVER") -or $upper.Contains("ODBC DRIVER")) {
    return "SQL Server"
  }
  return "unknown"
}

function Get-NativeAdaptiveEligibility {
  param([string]$DriverFamily)

  if ($DriverFamily -eq "SQL Server" -or $DriverFamily -eq "PostgreSQL") {
    return "eligible"
  }
  if ($DriverFamily -eq "SQL Anywhere") {
    return "blocked (lease/direct path)"
  }
  return "unknown"
}

function Get-DriverTuningRecommendation {
  param([string]$DriverFamily)

  switch ($DriverFamily) {
    "SQL Server" {
      return "Validate native/adaptive pool with driver matrix; tune ODBC_POOL_SIZE and SQL_QUEUE_MAX_WORKERS together, then watch transactional_native_pool_fallback."
    }
    "PostgreSQL" {
      return "Validate native/adaptive pool with driver matrix; prefer batched streaming for large SELECTs and watch pending saturation."
    }
    "SQL Anywhere" {
      return "Keep lease/direct path; tune SQL queue, direct limiter and bulkInsert instead of native pool."
    }
    default {
      return "Configure a representative DSN and run the driver matrix before changing pool defaults."
    }
  }
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
      if ($null -ne $runtime.result_encoding) {
        $Context.OdbcResultEncoding = [string]$runtime.result_encoding
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
    ('| Driver family | {0} |' -f $Context.DriverFamily),
    ('| Native/adaptive pool eligibility | {0} |' -f $Context.NativeAdaptiveEligibility),
    ('| Smoke query | `{0}` |' -f $Context.SmokeQuery),
    ('| Long query | `{0}` |' -f $Context.LongQuery),
    '',
    '## Effective Tuning',
    '',
    '```env',
    ('ODBC_POOL_SIZE={0}' -f $Context.OdbcPoolSize),
    ('ODBC_ASYNC_WORKER_COUNT={0}' -f $Context.OdbcAsyncWorkerCount),
    ('ODBC_ASYNC_MAX_PENDING_REQUESTS={0}' -f $Context.OdbcAsyncMaxPendingRequests),
    ('ODBC_RESULT_ENCODING={0}' -f $Context.OdbcResultEncoding),
    ('SQL_QUEUE_MAX_SIZE={0}' -f $Context.SqlQueueMaxSize),
    ('SQL_QUEUE_MAX_WORKERS={0}' -f $Context.SqlQueueMaxWorkers),
    ('SQL_QUEUE_TIMEOUT_SEC={0}' -f $Context.SqlQueueTimeoutSec),
    ('ODBC_POOL_ACQUIRE_TIMEOUT_SEC={0}' -f $Context.PoolAcquireTimeoutSec),
    ('CIRCUIT_BREAKER_FAILURE_THRESHOLD={0}' -f $Context.CircuitBreakerFailureThreshold),
    ('CIRCUIT_BREAKER_RESET_SEC={0}' -f $Context.CircuitBreakerResetSec),
    ('RUN_ODBC_BURST_TESTS={0}' -f $Context.RunOdbcBurstTests),
    '```',
    '',
    'Driver recommendation:',
    '',
    ('> {0}' -f $Context.DriverTuningRecommendation),
    '',
    '## Step Status',
    '',
    '| Step | Status | Command |',
    '| --- | --- | --- |',
    ('| ODBC runtime | {0} | `{1}` |' -f $Steps.OdbcRuntime.Status, $Steps.OdbcRuntime.Command),
    ('| Preflight | {0} | `{1}` |' -f $Steps.Preflight.Status, $Steps.Preflight.Command),
    ('| Smoke | {0} | `{1}` |' -f $Steps.Smoke.Status, $Steps.Smoke.Command),
    ('| Burst | {0} | `{1}` |' -f $Steps.Burst.Status, $Steps.Burst.Command),
    ('| Benchmark | {0} | `{1}` |' -f $Steps.Benchmark.Status, $Steps.Benchmark.Command),
    ('| Streaming benchmark | {0} | `{1}` |' -f $Steps.StreamingBenchmark.Status, $Steps.StreamingBenchmark.Command),
    ('| Driver matrix benchmark | {0} | `{1}` |' -f $Steps.DriverMatrixBenchmark.Status, $Steps.DriverMatrixBenchmark.Command),
    '',
    '## Step Artifacts',
    '',
    '| Step | Log | Started at | Finished at |',
    '| --- | --- | --- | --- |',
    ('| ODBC runtime | {0} | {1} | {2} |' -f $Steps.OdbcRuntime.Log, $Steps.OdbcRuntime.StartedAt, $Steps.OdbcRuntime.FinishedAt),
    ('| Preflight | {0} | {1} | {2} |' -f $Steps.Preflight.Log, $Steps.Preflight.StartedAt, $Steps.Preflight.FinishedAt),
    ('| Smoke | {0} | {1} | {2} |' -f $Steps.Smoke.Log, $Steps.Smoke.StartedAt, $Steps.Smoke.FinishedAt),
    ('| Burst | {0} | {1} | {2} |' -f $Steps.Burst.Log, $Steps.Burst.StartedAt, $Steps.Burst.FinishedAt),
    ('| Benchmark | {0} | {1} | {2} |' -f $Steps.Benchmark.Log, $Steps.Benchmark.StartedAt, $Steps.Benchmark.FinishedAt),
    ('| Streaming benchmark | {0} | {1} | {2} |' -f $Steps.StreamingBenchmark.Log, $Steps.StreamingBenchmark.StartedAt, $Steps.StreamingBenchmark.FinishedAt),
    ('| Driver matrix benchmark | {0} | {1} | {2} |' -f $Steps.DriverMatrixBenchmark.Log, $Steps.DriverMatrixBenchmark.StartedAt, $Steps.DriverMatrixBenchmark.FinishedAt),
    '',
    '## Auxiliary Artifacts',
    '',
    '| Artifact | Purpose |',
    '| --- | --- |',
    '| `health_snapshot_template.json` | Template no shape atual de `agent.getHealth` com tuning efetivo do ambiente local. |',
    '| `odbc_runtime.log` | Smoke sem DSN para inicializacao do `odbc_fast`, worker async e exports columnar/compressed. |',
    '| `health_burst_*_before.json` / `health_burst_*_after.json` | Snapshots reais de `HealthService.getHealthStatusAsync()` gravados pelo teste de burst quando `-RunBurst`/`-All` roda. |',
    '| `driver_matrix_*_async.log` / `driver_matrix_*_streaming.log` | Benchmark por driver configurado; drivers sem DSN sao pulados. |',
    '',
    '## Automated Health Snapshots',
    '',
    'When Burst runs, `sql_queue_burst_test.dart` receives `ODBC_BURST_HEALTH_SNAPSHOT_DIR` and writes before/after health JSON files into the run directory. If the Burst step is not requested, collect `agent.getHealth` manually before making tuning decisions.',
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
  $RunStreamingBenchmark = $true
  $RunDriverMatrixBenchmark = $true
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
  OdbcResultEncoding = Get-EffectiveEnvValue @("ODBC_RESULT_ENCODING")
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

$context.DriverFamily = Get-DsnDriverFamily $context.DsnUsed
$context.NativeAdaptiveEligibility = Get-NativeAdaptiveEligibility $context.DriverFamily
$context.DriverTuningRecommendation = Get-DriverTuningRecommendation $context.DriverFamily

if ([string]::IsNullOrWhiteSpace($context.LongQuery)) {
  $context.LongQuery = "(not configured)"
}

if ([string]::IsNullOrWhiteSpace($context.CircuitBreakerFailureThreshold)) {
  $context.CircuitBreakerFailureThreshold = "5"
}

if ([string]::IsNullOrWhiteSpace($context.CircuitBreakerResetSec)) {
  $context.CircuitBreakerResetSec = "30"
}

if ([string]::IsNullOrWhiteSpace($context.OdbcResultEncoding)) {
  $context.OdbcResultEncoding = "rowMajor"
}

$steps = @{
  OdbcRuntime = @{
    Status = "pending"
    Command = "dart run tool/check_odbc_fast_runtime.dart --require-columnar-compressed"
    Log = "odbc_runtime.log"
    StartedAt = "-"
    FinishedAt = "-"
  }
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
  StreamingBenchmark = @{
    Status = if ($RunStreamingBenchmark) { "pending" } else { "not requested" }
    Command = ".\tool\odbc_streaming_benchmark.ps1"
    Log = if ($RunStreamingBenchmark) { "streaming_benchmark.log" } else { "(not requested)" }
    StartedAt = "-"
    FinishedAt = "-"
  }
  DriverMatrixBenchmark = @{
    Status = if ($RunDriverMatrixBenchmark) { "pending" } else { "not requested" }
    Command = ".\tool\odbc_driver_matrix_benchmark.ps1 -OutputDirectory <runDirectory>"
    Log = if ($RunDriverMatrixBenchmark) { "driver_matrix.log" } else { "(not requested)" }
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

  $odbcRuntimeResult = Invoke-StepCommand -Name "ODBC runtime" -CommandText $steps.OdbcRuntime.Command -LogPath (Join-Path $runDirectory $steps.OdbcRuntime.Log) -Command {
    dart run tool/check_odbc_fast_runtime.dart --require-columnar-compressed
  }
  $steps.OdbcRuntime.Status = if ($odbcRuntimeResult.Succeeded) { "passed" } else { "failed" }
  $steps.OdbcRuntime.StartedAt = $odbcRuntimeResult.StartedAt
  $steps.OdbcRuntime.FinishedAt = $odbcRuntimeResult.FinishedAt
  if (-not $odbcRuntimeResult.Succeeded) {
    $failureDetected = $true
    throw "ODBC runtime failed."
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
    $env:ODBC_BURST_HEALTH_SNAPSHOT_DIR = $runDirectory
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

  if ($RunStreamingBenchmark) {
    $streamingBenchmarkResult = Invoke-StepCommand -Name "Streaming benchmark" -CommandText $steps.StreamingBenchmark.Command -LogPath (Join-Path $runDirectory $steps.StreamingBenchmark.Log) -Command {
      & (Join-Path $repoRoot "tool\odbc_streaming_benchmark.ps1")
    }
    $steps.StreamingBenchmark.Status = if ($streamingBenchmarkResult.Succeeded) { "passed" } else { "failed" }
    $steps.StreamingBenchmark.StartedAt = $streamingBenchmarkResult.StartedAt
    $steps.StreamingBenchmark.FinishedAt = $streamingBenchmarkResult.FinishedAt
    if (-not $streamingBenchmarkResult.Succeeded) {
      $failureDetected = $true
      throw "Streaming benchmark failed."
    }
  }

  if ($RunDriverMatrixBenchmark) {
    $driverMatrixResult = Invoke-StepCommand -Name "Driver matrix benchmark" -CommandText $steps.DriverMatrixBenchmark.Command -LogPath (Join-Path $runDirectory $steps.DriverMatrixBenchmark.Log) -Command {
      & (Join-Path $repoRoot "tool\odbc_driver_matrix_benchmark.ps1") -OutputDirectory $runDirectory
    }
    $steps.DriverMatrixBenchmark.Status = if ($driverMatrixResult.Succeeded) { "passed" } else { "failed" }
    $steps.DriverMatrixBenchmark.StartedAt = $driverMatrixResult.StartedAt
    $steps.DriverMatrixBenchmark.FinishedAt = $driverMatrixResult.FinishedAt
    if (-not $driverMatrixResult.Succeeded) {
      $failureDetected = $true
      throw "Driver matrix benchmark failed."
    }
  }
}
finally {
  $report = New-ValidationReport -Context $context -Steps $steps
  Set-Content -LiteralPath $reportPath -Value $report -Encoding UTF8
  Write-Host ""
  Write-Host "Validation worksheet: $reportPath" -ForegroundColor Gray
  Write-Host "Run artifacts directory: $runDirectory" -ForegroundColor Gray
  Write-Host "Burst health snapshots are written automatically when -RunBurst or -All is used." -ForegroundColor Gray
  Pop-Location
}

if ($failureDetected) {
  exit 1
}

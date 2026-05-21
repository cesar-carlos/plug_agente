param(
  [string]$EnvPath = ".env",
  [string]$OutputDirectory = ""
)

$ErrorActionPreference = "Stop"

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

function Invoke-BenchmarkForDriver {
  param(
    [string]$DriverName,
    [string]$DriverSlug,
    [string]$Dsn,
    [string]$LongQuery,
    [string]$OutputDirectory
  )

  if ([string]::IsNullOrWhiteSpace($Dsn)) {
    Write-Host "Skipping ${DriverName}: DSN not configured"
    return
  }

  Write-Host ""
  Write-Host "==> $DriverName" -ForegroundColor Cyan
  Write-Host "Native/adaptive pool eligible: $($DriverName -ne 'SQL Anywhere')"

  $previousDsn = $env:ODBC_TEST_DSN
  $previousStreamQuery = $env:ODBC_STREAM_BENCH_QUERY
  try {
    $env:ODBC_TEST_DSN = $Dsn
    [Environment]::SetEnvironmentVariable("ODBC_STREAM_BENCH_QUERY", $null, "Process")

    $asyncCommand = { & (Join-Path $PSScriptRoot "odbc_async_benchmark.ps1") }
    $streamCommand = { & (Join-Path $PSScriptRoot "odbc_streaming_benchmark.ps1") }

    if ([string]::IsNullOrWhiteSpace($OutputDirectory)) {
      & $asyncCommand
      if ($LASTEXITCODE -ne 0) {
        throw "$DriverName async benchmark failed"
      }
      & $streamCommand
      if ($LASTEXITCODE -ne 0) {
        throw "$DriverName streaming benchmark failed"
      }
      return
    }

    if (-not (Test-Path -LiteralPath $OutputDirectory)) {
      New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
    }
    $asyncLog = Join-Path $OutputDirectory "driver_matrix_${DriverSlug}_async.log"
    $streamLog = Join-Path $OutputDirectory "driver_matrix_${DriverSlug}_streaming.log"

    & $asyncCommand *>&1 | Tee-Object -FilePath $asyncLog
    if ($LASTEXITCODE -ne 0) {
      throw "$DriverName async benchmark failed"
    }
    & $streamCommand *>&1 | Tee-Object -FilePath $streamLog
    if ($LASTEXITCODE -ne 0) {
      throw "$DriverName streaming benchmark failed"
    }
  } finally {
    if ($null -eq $previousDsn) {
      [Environment]::SetEnvironmentVariable("ODBC_TEST_DSN", $null, "Process")
    } else {
      $env:ODBC_TEST_DSN = $previousDsn
    }
    if ($null -eq $previousStreamQuery) {
      [Environment]::SetEnvironmentVariable("ODBC_STREAM_BENCH_QUERY", $null, "Process")
    } else {
      $env:ODBC_STREAM_BENCH_QUERY = $previousStreamQuery
    }
  }
}

$repoRoot = Split-Path -Parent $PSScriptRoot
$resolvedEnvPath = if ([System.IO.Path]::IsPathRooted($EnvPath)) {
  $EnvPath
} else {
  Join-Path $repoRoot $EnvPath
}

Import-DotEnvIfPresent -Path $resolvedEnvPath

$drivers = @(
  @{
    Name = "SQL Anywhere"
    Slug = "sql_anywhere"
    Dsn = Get-EffectiveEnvValue @("ODBC_TEST_DSN", "ODBC_DSN")
    LongQuery = Get-EffectiveEnvValue @("ODBC_INTEGRATION_LONG_QUERY_SQL_ANYWHERE", "ODBC_INTEGRATION_LONG_QUERY")
  },
  @{
    Name = "SQL Server"
    Slug = "sql_server"
    Dsn = Get-EffectiveEnvValue @("ODBC_TEST_DSN_SQL_SERVER", "ODBC_DSN_SQL_SERVER")
    LongQuery = Get-EffectiveEnvValue @("ODBC_INTEGRATION_LONG_QUERY_SQL_SERVER", "ODBC_INTEGRATION_LONG_QUERY")
  },
  @{
    Name = "PostgreSQL"
    Slug = "postgresql"
    Dsn = Get-EffectiveEnvValue @("ODBC_TEST_DSN_POSTGRESQL", "ODBC_DSN_POSTGRESQL")
    LongQuery = Get-EffectiveEnvValue @("ODBC_INTEGRATION_LONG_QUERY_POSTGRESQL", "ODBC_INTEGRATION_LONG_QUERY")
  }
)

$configured = 0
foreach ($driver in $drivers) {
  if (-not [string]::IsNullOrWhiteSpace($driver.Dsn)) {
    $configured++
  }
}

Write-Host "Running ODBC driver benchmark matrix"
Write-Host "Configured drivers: $configured"

if ($configured -eq 0) {
  Write-Host "No DSN configured; nothing to benchmark."
  exit 0
}

foreach ($driver in $drivers) {
  Invoke-BenchmarkForDriver `
    -DriverName $driver.Name `
    -DriverSlug $driver.Slug `
    -Dsn $driver.Dsn `
    -LongQuery $driver.LongQuery `
    -OutputDirectory $OutputDirectory
}

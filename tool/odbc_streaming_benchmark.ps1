param(
  [string]$BenchmarkPath = "D:\Developer\dart_odbc_fast\example\streaming_performance_benchmark.dart",
  [string]$EnvPath = ".env"
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

    if ([Environment]::GetEnvironmentVariable($key, "Process")) {
      continue
    }

    [Environment]::SetEnvironmentVariable($key, $value, "Process")
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

function Get-DsnDriverFamily {
  param([string]$ConnectionString)

  $upper = $ConnectionString.ToUpperInvariant()
  if ($upper.Contains("POSTGRE")) {
    return "PostgreSQL"
  }
  if ($upper.Contains("ANYWHERE") -or $upper.Contains("SYBASE") -or $upper.Contains("SQLA")) {
    return "SQL Anywhere"
  }
  if ($upper.Contains("SQL SERVER") -or $upper.Contains("ODBC DRIVER") -or $upper.Contains("NATIVE CLIENT")) {
    return "SQL Server"
  }
  return "unknown"
}

function Get-LongQueryForDriver {
  param([string]$DriverFamily)

  switch ($DriverFamily) {
    "SQL Anywhere" {
      return Get-EffectiveEnvValue @("ODBC_INTEGRATION_LONG_QUERY_SQL_ANYWHERE", "ODBC_INTEGRATION_LONG_QUERY")
    }
    "SQL Server" {
      return Get-EffectiveEnvValue @("ODBC_INTEGRATION_LONG_QUERY_SQL_SERVER", "ODBC_INTEGRATION_LONG_QUERY")
    }
    "PostgreSQL" {
      return Get-EffectiveEnvValue @("ODBC_INTEGRATION_LONG_QUERY_POSTGRESQL", "ODBC_INTEGRATION_LONG_QUERY")
    }
    default {
      return Get-EffectiveEnvValue @("ODBC_INTEGRATION_LONG_QUERY")
    }
  }
}

$resolvedBenchmark = Resolve-Path -LiteralPath $BenchmarkPath -ErrorAction Stop
$benchmarkFile = Get-Item -LiteralPath $resolvedBenchmark
$exampleDir = $benchmarkFile.Directory
$packageRoot = $exampleDir.Parent.FullName
$benchmarkRelativePath = "example/$($benchmarkFile.Name)"

Import-DotEnvIfPresent -Path $EnvPath

if (-not $env:ODBC_TEST_DSN -and $env:ODBC_DSN) {
  $env:ODBC_TEST_DSN = $env:ODBC_DSN
}

$streamQuerySource = "explicit"
if ([string]::IsNullOrWhiteSpace($env:ODBC_STREAM_BENCH_QUERY)) {
  $driverFamily = Get-DsnDriverFamily $env:ODBC_TEST_DSN
  $longQuery = Get-LongQueryForDriver $driverFamily
  if (-not [string]::IsNullOrWhiteSpace($longQuery)) {
    $env:ODBC_STREAM_BENCH_QUERY = $longQuery
    $streamQuerySource = "ODBC_INTEGRATION_LONG_QUERY ($driverFamily)"
  } else {
    $streamQuerySource = "benchmark_default"
  }
}

Write-Host "Running odbc_fast streaming benchmark"
Write-Host "Benchmark: $resolvedBenchmark"
Write-Host "Package root: $packageRoot"
Write-Host "ODBC_TEST_DSN configured: $([bool]$env:ODBC_TEST_DSN)"
Write-Host "ODBC_STREAM_BENCH_QUERY=$env:ODBC_STREAM_BENCH_QUERY"
Write-Host "ODBC_STREAM_BENCH_QUERY_SOURCE=$streamQuerySource"
Write-Host "ODBC_STREAM_BENCH_FETCH_SIZE=$env:ODBC_STREAM_BENCH_FETCH_SIZE"
Write-Host "ODBC_STREAM_BENCH_CHUNK_SIZE=$env:ODBC_STREAM_BENCH_CHUNK_SIZE"

function Invoke-DartBenchmark {
  param([object[]]$BenchmarkArgs)

  $previousErrorActionPreference = $ErrorActionPreference
  $ErrorActionPreference = "Continue"
  try {
    $output = & dart run $benchmarkRelativePath @BenchmarkArgs 2>&1
    $code = $LASTEXITCODE
  } catch {
    $output = @($_)
    $code = if ($LASTEXITCODE -ne $null) { $LASTEXITCODE } else { 1 }
  } finally {
    $ErrorActionPreference = $previousErrorActionPreference
  }
  return @{
    ExitCode = $code
    Output = $output
  }
}

$exitCode = 0
$benchmarkArgs = $args
Push-Location -LiteralPath $packageRoot
try {
  $run = Invoke-DartBenchmark -BenchmarkArgs $benchmarkArgs
  $exitCode = $run.ExitCode
  if ($exitCode -eq 0) {
    $run.Output | Write-Output
  } elseif ($streamQuerySource -ne "explicit") {
    Write-Warning "Streaming benchmark failed with auto-selected long query; retrying with package default query."
    [Environment]::SetEnvironmentVariable("ODBC_STREAM_BENCH_QUERY", $null, "Process")
    $fallbackRun = Invoke-DartBenchmark -BenchmarkArgs $benchmarkArgs
    $exitCode = $fallbackRun.ExitCode
    $fallbackRun.Output | Write-Output
  } else {
    $run.Output | Write-Output
  }
} finally {
  Pop-Location
}

exit $exitCode

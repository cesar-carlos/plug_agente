param(
  [string]$BenchmarkPath = "D:\Developer\dart_odbc_fast\example\async_concurrency_benchmark.dart",
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

$resolvedBenchmark = Resolve-Path -LiteralPath $BenchmarkPath -ErrorAction Stop
$benchmarkFile = Get-Item -LiteralPath $resolvedBenchmark
$exampleDir = $benchmarkFile.Directory
$packageRoot = $exampleDir.Parent.FullName
$benchmarkRelativePath = "example/$($benchmarkFile.Name)"

Import-DotEnvIfPresent -Path $EnvPath

if (-not $env:ODBC_TEST_DSN -and $env:ODBC_DSN) {
  $env:ODBC_TEST_DSN = $env:ODBC_DSN
}

Write-Host "Running odbc_fast async concurrency benchmark"
Write-Host "Benchmark: $resolvedBenchmark"
Write-Host "Package root: $packageRoot"
Write-Host "ODBC_TEST_DSN configured: $([bool]$env:ODBC_TEST_DSN)"
Write-Host "ODBC_POOL_SIZE=$env:ODBC_POOL_SIZE"
Write-Host "ODBC_ASYNC_WORKER_COUNT=$env:ODBC_ASYNC_WORKER_COUNT"
Write-Host "ODBC_ASYNC_MAX_PENDING_REQUESTS=$env:ODBC_ASYNC_MAX_PENDING_REQUESTS"

$exitCode = 0
Push-Location -LiteralPath $packageRoot
try {
  dart run $benchmarkRelativePath @args
  $exitCode = $LASTEXITCODE
} finally {
  Pop-Location
}

exit $exitCode

# Captures DML stress timings from flutter test output into benchmark_logs/stress_baseline.json
param(
    [string]$OutputFile = 'benchmark_logs/stress_baseline.json',
    [string]$TestPath = 'test/live/odbc_dml_stress_live_e2e_test.dart'
)

$ErrorActionPreference = 'Stop'
$root = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
Set-Location $root

$logFile = Join-Path $env:TEMP "plug_agente_stress_capture_$([Guid]::NewGuid().ToString('N')).txt"
try {
    flutter test $TestPath --reporter expanded 2>&1 | Tee-Object -FilePath $logFile
    $exitCode = $LASTEXITCODE

    $content = Get-Content $logFile -Raw
    $insertMs = if ($content -match 'insert_ms[:\s]+(\d+)') { [int]$Matches[1] } else { $null }
    $updateMs = if ($content -match 'update_ms[:\s]+(\d+)') { [int]$Matches[1] } else { $null }
    $deleteMs = if ($content -match 'delete_ms[:\s]+(\d+)') { [int]$Matches[1] } else { $null }
    $totalMs = if ($content -match 'total_ms[:\s]+(\d+)') { [int]$Matches[1] } else { $null }

    $outDir = Split-Path $OutputFile -Parent
    if ($outDir -and -not (Test-Path $outDir)) {
        New-Item -ItemType Directory -Path $outDir -Force | Out-Null
    }

    $payload = [ordered]@{
        captured_at = (Get-Date).ToUniversalTime().ToString('o')
        source_test = $TestPath
        flutter_exit_code = $exitCode
        timings_ms = [ordered]@{
            insert = $insertMs
            update = $updateMs
            delete = $deleteMs
            total = $totalMs
        }
        log_excerpt = ($content -split "`n" | Select-Object -Last 40) -join "`n"
    }
    $payload | ConvertTo-Json -Depth 6 | Set-Content -Path $OutputFile -Encoding utf8
    Write-Host "Wrote $OutputFile" -ForegroundColor Green
    exit $exitCode
}
finally {
    if (Test-Path $logFile) { Remove-Item $logFile -Force }
}

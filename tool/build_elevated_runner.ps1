$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$packageDir = Join-Path $repoRoot "tool\plug_agente_elevated_runner"
$outputDir = Join-Path $repoRoot "build\elevated_runner"
$outputExe = Join-Path $outputDir "plug_agente_elevated_runner.exe"

Push-Location $packageDir
try {
  dart pub get
  if (-not (Test-Path $outputDir)) {
    New-Item -ItemType Directory -Path $outputDir | Out-Null
  }
  dart compile exe bin/plug_agente_elevated_runner.dart -o $outputExe
  Write-Host "Built elevated runner helper: $outputExe"

  $bundleTargets = @(
    (Join-Path $repoRoot "build\windows\x64\runner\Release"),
    (Join-Path $repoRoot "build\windows\x64\runner\Debug")
  )
  foreach ($bundleDir in $bundleTargets) {
    if (Test-Path $bundleDir) {
      Copy-Item -Path $outputExe -Destination (Join-Path $bundleDir "plug_agente_elevated_runner.exe") -Force
      Write-Host "Copied helper to: $bundleDir"
    }
  }
}
finally {
  Pop-Location
}

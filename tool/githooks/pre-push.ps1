# Optional pre-push gate for release-sensitive paths on main.
# Skip entirely: $env:SKIP_RELEASE_GATE = '1'
# Install: .\tool\install_git_hooks.ps1

$ErrorActionPreference = 'Stop'

if ($env:SKIP_RELEASE_GATE -eq '1') {
  exit 0
}

$branch = (git rev-parse --abbrev-ref HEAD 2>$null).Trim()
if ($branch -ne 'main') {
  exit 0
}

$stdin = [Console]::In.ReadToEnd().Trim()
if ($stdin) {
  $firstLine = ($stdin -split "`n")[0].Trim()
  $parts = $firstLine -split '\s+'
  if ($parts.Count -ge 3) {
    $remoteRef = $parts[2]
    if ($remoteRef -and $remoteRef -notmatch 'refs/heads/main$') {
      exit 0
    }
  }
}

$upstream = 'origin/main'
$changed = @(git diff --name-only "$upstream...HEAD" 2>$null)
if ($changed.Count -eq 0) {
  $changed = @(git diff --name-only --cached 2>$null)
}

$pattern = '^(pubspec\.yaml|lib/|test/|tool/release_preflight\.py|tool/pre_publish_release\.ps1)'
$releaseSensitive = $false
foreach ($path in $changed) {
  if ($path -match $pattern) {
    $releaseSensitive = $true
    break
  }
}

if (-not $releaseSensitive) {
  exit 0
}

Write-Host 'pre-push: running release gate (--gate) for release-sensitive changes on main...' -ForegroundColor Cyan
$repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..\..')
Push-Location $repoRoot
try {
  python tool/release_preflight.py --gate --allow-dirty --allow-existing-tag --check-secrets
  if ($LASTEXITCODE -ne 0) {
    Write-Host 'pre-push: release gate failed. Fix issues or push with SKIP_RELEASE_GATE=1.' -ForegroundColor Red
    exit 1
  }
}
finally {
  Pop-Location
}

exit 0

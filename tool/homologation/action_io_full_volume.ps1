param(
    [string]$Dart = 'C:\Users\cesar\dev\flutter\bin\cache\dart-sdk\bin\dart.exe',
    [string]$FlutterTools = 'C:\Users\cesar\dev\flutter\bin\cache\flutter_tools.snapshot'
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$principal = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw 'Private VHD acceptance requires an administrative PowerShell. No disk was created or modified.'
}
$repo = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$identity = [Guid]::NewGuid().ToString('N')
$private = Join-Path ([IO.Path]::GetTempPath()) "action-io-volume-$identity"
$null = New-Item -ItemType Directory -Path $private
$image = Join-Path $private 'fixture.vhdx'
$mounted = $false
$testPassed = $false
try {
    # Only a newly created, bounded image is ever initialized or formatted.
    $null = New-VHD -Path $image -SizeBytes 128MB -Dynamic
    $null = Mount-VHD -Path $image -NoDriveLetter
    $mounted = $true
    $vhd = Get-VHD -Path $image
    $disk = Get-Disk -Number $vhd.DiskNumber
    if ($vhd.Size -ne 128MB -or $disk.Size -ne 128MB -or $disk.IsSystem -or $disk.IsBoot -or $disk.PartitionStyle -ne 'RAW') {
        throw 'Fresh private VHD identity/capacity preflight failed.'
    }
    $null = $disk | Initialize-Disk -PartitionStyle GPT
    $partition = New-Partition -DiskNumber $disk.Number -UseMaximumSize -AssignDriveLetter
    $volume = $partition | Format-Volume -FileSystem NTFS -NewFileSystemLabel 'ActionIoFixture' -Confirm:$false
    if ($volume.Size -gt 128MB -or $volume.Size -lt 32MB -or $volume.DriveLetter -in @('C', 'D')) {
        throw 'Private volume verification failed.'
    }
    $root = Join-Path "$($volume.DriveLetter):\" "fixture-$identity"
    $null = New-Item -ItemType Directory -Path $root
    Set-Content -LiteralPath (Join-Path $root 'identity') -Value $identity -NoNewline
    $env:ACTION_IO_FULL_VOLUME_ROOT = $root
    $env:ACTION_IO_FULL_VOLUME_ID = $identity
    Push-Location $repo
    try {
        & $Dart $FlutterTools test --no-pub --reporter expanded tool/homologation/action_io_full_volume_test.dart 2>&1 |
            Tee-Object -FilePath (Join-Path $private 'test.log')
        if ($LASTEXITCODE -ne 0) { throw "Full-volume acceptance failed: $LASTEXITCODE" }
        $testPassed = $true
    } finally { Pop-Location }
} finally {
    Remove-Item Env:ACTION_IO_FULL_VOLUME_ROOT -ErrorAction SilentlyContinue
    Remove-Item Env:ACTION_IO_FULL_VOLUME_ID -ErrorAction SilentlyContinue
    if ($mounted) { Dismount-VHD -Path $image }
    if ($testPassed) {
        @{
            status = 'passed'
            volumeDismounted = $true
            capacityBytes = 128MB
            identity = $identity
            testSha256 = (Get-FileHash -LiteralPath (Join-Path $PSScriptRoot 'action_io_full_volume_test.dart') -Algorithm SHA256).Hash
        } | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $private 'result.json')
    }
    # Retain the bounded image for inspection; never recursively remove a mount.
    Write-Output "Private volume evidence retained at $private"
}

# Smoke test E2E para instância única do Plug Agente.
# Pré-requisito: app compilado em build\windows\x64\runner\Debug\plug_agente.exe
# Ou: build\windows\x64\runner\Release\plug_agente.exe
#
# Cenários:
# 1. Abre app, tenta abrir novamente -> deve mostrar MessageBox
# 2. Abre app, tenta abrir com --autostart -> deve encerrar silenciosamente

$ErrorActionPreference = "Stop"
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$rootDir = Split-Path -Parent $scriptDir

$exeDebug = "$rootDir\build\windows\x64\runner\Debug\plug_agente.exe"
$exeRelease = "$rootDir\build\windows\x64\runner\Release\plug_agente.exe"

$exe = $null
if (Test-Path $exeDebug) { $exe = $exeDebug }
elseif (Test-Path $exeRelease) { $exe = $exeRelease }
else {
  Write-Error "Nenhum executável encontrado. Execute 'flutter build windows' primeiro."
  exit 1
}

Write-Host "Usando: $exe"
Write-Host ""

# Garantir que não há instâncias rodando
Get-Process -Name "plug_agente" -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 2

Write-Host "Cenário 1: Abrir app normalmente..."
$p1 = Start-Process -FilePath $exe -PassThru -WindowStyle Normal
Start-Sleep -Seconds 3

Write-Host "Cenário 1: Tentar abrir segunda instância (manual)..."
$p2 = Start-Process -FilePath $exe -PassThru -WindowStyle Normal
Start-Sleep -Seconds 2

# Segunda instância deve ter encerrado rapidamente (MessageBox pode estar aberta)
$p2StillRunning = $false
try { $p2StillRunning = -not $p2.HasExited } catch { $p2StillRunning = $false }
if ($p2StillRunning) {
  Write-Host "AVISO: Segunda instância ainda está rodando. Verifique se a MessageBox foi exibida."
} else {
  Write-Host "OK: Segunda instância encerrou (MessageBox deve ter sido exibida)."
}

Write-Host ""
Write-Host "Cenário 2: Tentar abrir com --autostart..."
$p3 = Start-Process -FilePath $exe -ArgumentList "--autostart" -PassThru -WindowStyle Hidden
Start-Sleep -Seconds 2

$p3StillRunning = $false
try { $p3StillRunning = -not $p3.HasExited } catch { $p3StillRunning = $false }
if ($p3StillRunning) {
  Write-Host "AVISO: Terceira instância (--autostart) ainda está rodando. Deveria ter encerrado silenciosamente."
  $p3 | Stop-Process -Force -ErrorAction SilentlyContinue
} else {
  Write-Host "OK: Instância --autostart encerrou silenciosamente."
}

Write-Host ""
Write-Host "Encerrando primeira instância..."
$p1 | Stop-Process -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 1

Write-Host "Teste concluído. Revise os resultados acima."

# Desktop / shortcut launch for Fluxidi lokale test.
# Does not rebuild and does not touch production Fluxidi.
# Checks the local Worker and starts it if needed, keeping persist.
param(
  [switch]$NoLaunch
)

$ErrorActionPreference = 'Stop'
$repo = Split-Path $PSScriptRoot -Parent
$dest = Join-Path $repo 'build\windows\starts\Fluxidi_lokale_test'
$exe = Join-Path $dest 'fluxidi_tracking.exe'

& (Join-Path $PSScriptRoot 'ensure_local_customer_ops_worker.ps1')

if (-not (Test-Path -LiteralPath $exe)) {
  throw "Lokale startkopie ontbreekt: $exe. Bouw eerst via start_fluxidi_lokale_test_windows.ps1"
}

if ($NoLaunch) { return }

Start-Process -FilePath $exe -WorkingDirectory $dest
Write-Host 'Launched Fluxidi lokale test'
Write-Host "Exe: $exe"

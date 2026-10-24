# Start or reuse the local booking demo Worker. Never wipes persist.
# Health: http://127.0.0.1:8788/local/health
# Persist: workers/booking/.local-customer-ops-demo\
param(
  [string]$WorkerRoot = 'C:\_flutter_work\fluxidi_customer_ops_worker_p0\workers\booking',
  [string]$HealthUrl = 'http://127.0.0.1:8788/local/health'
)

$ErrorActionPreference = 'Stop'
$demo = Join-Path $WorkerRoot 'local_customer_ops_demo.mjs'
$persist = Join-Path $WorkerRoot '.local-customer-ops-demo'
if (-not (Test-Path -LiteralPath $demo)) {
  throw "Local Worker script missing: $demo"
}

$devEnv = Join-Path $env:USERPROFILE '.fluxidi\fluxidi-dev-env.ps1'
if (Test-Path -LiteralPath $devEnv) {
  . $devEnv
  Write-Host 'Fluxidi env file loaded for local Worker (secret values hidden)'
}

function Test-LocalCustomerOpsWorker {
  try {
    $response = Invoke-WebRequest -Uri $HealthUrl -UseBasicParsing -TimeoutSec 3
    return ($response.StatusCode -eq 200 -and $response.Content -match '"ok"\s*:\s*true')
  } catch {
    return $false
  }
}

function Test-LocalWorkerMapboxConfigured {
  try {
    $response = Invoke-WebRequest -Uri $HealthUrl -UseBasicParsing -TimeoutSec 3
    return ($response.StatusCode -eq 200 -and $response.Content -match '"mapbox_configured"\s*:\s*true')
  } catch {
    return $false
  }
}

function Stop-LocalCustomerOpsWorker {
  Write-Host ("{0} stopping FluxidiLocalWorker window if present (persist kept)" -f (Get-Date -Format o))
  cmd.exe /c 'taskkill /F /FI "WINDOWTITLE eq FluxidiLocalWorker*" >nul 2>&1'
}

$mapboxPresent = -not [string]::IsNullOrWhiteSpace(
  [Environment]::GetEnvironmentVariable('MAPBOX_TOKEN', 'Process')
)
if ($mapboxPresent) {
  Write-Host 'MAPBOX_TOKEN present for local Worker (waarde verborgen)'
} else {
  Write-Host "MAPBOX_TOKEN missing for local Worker. Expected source: $devEnv"
}

if (Test-LocalCustomerOpsWorker) {
  if ($mapboxPresent -and -not (Test-LocalWorkerMapboxConfigured)) {
    Write-Host 'Local Worker is up without Mapbox config; restarting and keeping persist'
    Stop-LocalCustomerOpsWorker
    Start-Sleep -Milliseconds 600
  } else {
    Write-Host "Local Worker already up: $HealthUrl"
    Write-Host "Persist kept: $persist"
    return
  }
}

New-Item -ItemType Directory -Force -Path $persist | Out-Null
Write-Host "Starting local Worker (persist kept): $persist"
# Detach from this script's job so the Worker keeps running after the
# start script ends. ProcessStartInfo inherits the current env (including
# MAPBOX_TOKEN) without printing it; `cmd start` then breaks away.
$psi = New-Object System.Diagnostics.ProcessStartInfo
$psi.FileName = 'cmd.exe'
$psi.Arguments = '/c start "FluxidiLocalWorker" /min node local_customer_ops_demo.mjs'
$psi.WorkingDirectory = $WorkerRoot
$psi.UseShellExecute = $false
$psi.CreateNoWindow = $true
[void][System.Diagnostics.Process]::Start($psi)

$deadline = (Get-Date).AddSeconds(25)
while ((Get-Date) -lt $deadline) {
  if (Test-LocalCustomerOpsWorker) {
    Write-Host "Local Worker ready: $HealthUrl"
    return
  }
  Start-Sleep -Milliseconds 400
}

throw "Local Worker did not become ready at $HealthUrl"

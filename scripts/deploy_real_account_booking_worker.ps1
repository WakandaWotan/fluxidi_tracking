# Production Booking Worker deploy for FLX-00001 / Fluxidi.
# Refuses to run unless -IApproveProductionDeploy is passed.
# Uses wrangler.real-account-release.toml and --keep-vars.

param(
  [switch]$IApproveProductionDeploy
)

$ErrorActionPreference = 'Stop'
if (-not $IApproveProductionDeploy) {
  throw 'Refusing to deploy. Pass -IApproveProductionDeploy only after Christophe approves this exact production Worker release.'
}

$worker = 'C:\_flutter_work\fluxidi_customer_ops_worker_p0\workers\booking'
$config = 'wrangler.real-account-release.toml'
$configPath = Join-Path $worker $config
$outDir = 'C:\_flutter_work\fluxidi_customer_ops_client_p0\.qa-local\real-account'
New-Item -ItemType Directory -Force -Path $outDir | Out-Null
if (-not (Test-Path -LiteralPath $configPath)) {
  throw "Missing release config: $configPath"
}
Set-Location -LiteralPath $worker

node --check .\fluxidi_booking_worker.js
if ($LASTEXITCODE -ne 0) { throw "node --check failed: $LASTEXITCODE" }

Write-Host 'Saving current deployments before overwrite...'
wrangler deployments list --config $configPath |
  Out-File -FilePath (Join-Path $outDir 'worker_deployments_before.txt') -Encoding utf8

Write-Host "Deploying fluxidi-booking-api with $config --keep-vars..."
wrangler deploy --config $configPath --keep-vars
if ($LASTEXITCODE -ne 0) { throw "wrangler deploy failed: $LASTEXITCODE" }

wrangler deployments list --config $configPath |
  Out-File -FilePath (Join-Path $outDir 'worker_deployments_after.txt') -Encoding utf8

Write-Host 'Post-deploy route check (no tokens): agenda should be 401, not 404'
curl.exe -sS -o (Join-Path $outDir 'agenda_after_deploy_body.txt') -w "agenda %{http_code}`n" --max-time 15 `
  "https://fluxidi-booking-api.fluxidi.workers.dev/company/agenda/rides"
Write-Host 'Done. Rollback: scripts/rollback_real_account_booking_worker.ps1'

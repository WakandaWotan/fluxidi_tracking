# Read-only preparation for the real-account Booking Worker release.
# Does not deploy, does not write KV, does not start the local demo Worker.

$ErrorActionPreference = 'Stop'
$worker = 'C:\_flutter_work\fluxidi_customer_ops_worker_p0\workers\booking'
$config = 'wrangler.real-account-release.toml'
$outDir = 'C:\_flutter_work\fluxidi_customer_ops_client_p0\.qa-local\real-account'
New-Item -ItemType Directory -Force -Path $outDir | Out-Null

if (-not (Test-Path -LiteralPath (Join-Path $worker 'fluxidi_booking_worker.js'))) {
  throw "Worker entry missing: $worker"
}
if (-not (Test-Path -LiteralPath (Join-Path $worker $config))) {
  throw "Release config missing: $config"
}

Set-Location -LiteralPath $worker
Write-Host 'prepare_real_account_booking_worker: syntax check'
node --check .\fluxidi_booking_worker.js
if ($LASTEXITCODE -ne 0) { throw "node --check failed: $LASTEXITCODE" }

Write-Host 'prepare_real_account_booking_worker: live deployments (read-only)'
$deployments = Join-Path $outDir 'worker_deployments_live.txt'
wrangler deployments list --config ".\$config" |
  Tee-Object -FilePath $deployments
if ($LASTEXITCODE -ne 0) {
  Write-Host "WARN: wrangler deployments list exit=$LASTEXITCODE"
}

Write-Host ''
Write-Host "Release config: $worker\$config"
Write-Host 'Adds: /company/customers, /company/agenda/*, /company/fixed-prices, /company/customer-quotes'
Write-Host 'Adds Durable Object CompanyCustomerImportCoordinator (new migration only)'
Write-Host 'No new RateHawk vars, test flags, or RATEHAWK_HOTELS_TEST'
Write-Host 'Keeps existing KV ids; --keep-vars keeps live secrets and extra vars'
Write-Host 'Does not copy demo_company_p0 or local persist'
Write-Host 'Rollback: scripts/rollback_real_account_booking_worker.ps1'
Write-Host 'Deploy only after approval: scripts/deploy_real_account_booking_worker.ps1 -IApproveProductionDeploy'

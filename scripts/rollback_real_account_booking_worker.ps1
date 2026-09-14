# Rollback the last fluxidi-booking-api deploy. Does not wipe KV.
# Restores the previous Cloudflare Worker version. Durable Object
# migration and any customer-ops keys written after deploy stay.

$ErrorActionPreference = 'Stop'
$worker = 'C:\_flutter_work\fluxidi_customer_ops_worker_p0\workers\booking'
$config = 'wrangler.real-account-release.toml'
Set-Location -LiteralPath $worker
Write-Host 'Rolling back fluxidi-booking-api to the previous Cloudflare version...'
wrangler rollback --config ".\$config"
if ($LASTEXITCODE -ne 0) { throw "wrangler rollback failed: $LASTEXITCODE" }
Write-Host 'Code rollback finished. Existing company KV was not deleted.'
Write-Host 'DO migration company-customer-import-coordinator-v1 is not undone.'

$ErrorActionPreference = "Stop"

$repo = "C:\_flutter_work\fluxidi_tracking"
$worker = "C:\_flutter_work\fluxidi_tracking\workers\tracking"

Set-Location $worker

if (-not (Test-Path ".\fluxidi_tracking_api_worker_V2_1_with_route_index.js")) {
  throw "Missing file: .\fluxidi_tracking_api_worker_V2_1_with_route_index.js"
}

if (-not (Test-Path ".\wrangler.toml")) {
  throw "Missing file: .\wrangler.toml"
}

Write-Host "Checking tracking worker syntax..."
node --check .\fluxidi_tracking_api_worker_V2_1_with_route_index.js

$deployCommand = 'wrangler deploy --config ".\wrangler.toml" --keep-vars'
Write-Host "Deploy command: $deployCommand"

wrangler deploy --config ".\wrangler.toml" --keep-vars

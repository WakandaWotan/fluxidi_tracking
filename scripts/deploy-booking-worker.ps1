$ErrorActionPreference = "Stop"

$repo = "C:\_flutter_work\fluxidi_tracking"
$worker = "C:\_flutter_work\fluxidi_tracking\workers\booking"

Set-Location $worker

if (-not (Test-Path ".\fluxidi_booking_worker.js")) {
  throw "Missing file: .\fluxidi_booking_worker.js"
}

if (-not (Test-Path ".\wrangler.toml")) {
  throw "Missing file: .\wrangler.toml"
}

Write-Host "Checking booking worker syntax..."
node --check .\fluxidi_booking_worker.js

$deployCommand = 'wrangler deploy --config ".\wrangler.toml" --keep-vars'
Write-Host "Deploy command: $deployCommand"

wrangler deploy --config ".\wrangler.toml" --keep-vars

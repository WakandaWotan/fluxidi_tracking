$ErrorActionPreference = "Stop"

$repo = "C:\_flutter_work\fluxidi_tracking"
$booking = "C:\_flutter_work\fluxidi_tracking\workers\booking"
$tracking = "C:\_flutter_work\fluxidi_tracking\workers\tracking"

Set-Location $repo

Write-Host "=== Repo status (full) ==="
git status --short

Write-Host ""
Write-Host "=== Repo status (workers/booking) ==="
git status --short -- workers/booking

Write-Host ""
Write-Host "=== Repo status (workers/tracking) ==="
git status --short -- workers/tracking

Write-Host ""
Write-Host "=== Node check (booking worker) ==="
Set-Location $booking
node --check .\fluxidi_booking_worker.js

Write-Host ""
Write-Host "=== Node check (tracking worker) ==="
Set-Location $tracking
node --check .\fluxidi_tracking_api_worker_V2_1_with_route_index.js

Set-Location $repo

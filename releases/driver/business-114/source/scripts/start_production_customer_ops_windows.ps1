# Flutter Windows desktop — full app shell against production booking.
# Named start point: Fluxidi. This is not a release/MSIX/install.
# Do not pass local BOOKING_BASE_URL. Leftover local demo sessions stay
# in the local-test storage folder and are not reused here.
# Local demo remains scripts/start_fluxidi_lokale_test_windows.ps1.
$ErrorActionPreference = 'Stop'
& (Join-Path $PSScriptRoot 'windows_start_env.ps1') -RuntimeEnv production

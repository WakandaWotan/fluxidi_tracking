# Fluxidi Google Play release AAB builder.
#
# Consumption-only company SaaS (no Mollie subscription checkout in the Play
# binary). Physical taxi ride payments are unchanged.
#
# Prerequisites (gitignored / local only):
#   - android/key.properties + upload keystore
#   - MAPBOX_TOKEN, WORKER_BASE_URL, BOOKING_BASE_URL in the environment
#
# Usage (from repo root):
#   powershell -File scripts/build_fluxidi_play_aab.ps1

$ErrorActionPreference = 'Stop'

function Assert-LastExitCode([string]$Step) {
    if ($LASTEXITCODE -ne 0) {
        throw "$Step failed with exit code $LASTEXITCODE"
    }
}

if (-not (Test-Path -LiteralPath 'android/key.properties')) {
    throw 'android/key.properties is missing. Configure the upload keystore first.'
}

# Load local Fluxidi env if present (does not print secret values).
$devEnv = Join-Path $env:USERPROFILE '.fluxidi\fluxidi-dev-env.ps1'
if (Test-Path -LiteralPath $devEnv) {
    . $devEnv
}

foreach ($name in @('MAPBOX_TOKEN', 'WORKER_BASE_URL', 'BOOKING_BASE_URL')) {
    $val = [Environment]::GetEnvironmentVariable($name)
    if ([string]::IsNullOrWhiteSpace($val)) {
        throw "$name is not set in the environment"
    }
}

$flutterArguments = @(
    'build',
    'appbundle',
    '--release',

    # Exact production field defines (12) + Play distribution gate.
    '--dart-define=NAV_COMPLEXITY_CLOUD_UPLOAD=true',
    '--dart-define=NAV_COMPLEXITY_FETCH_ADVISORY_RULES=true',
    '--dart-define=FLUXIDI_NAV_DRIVER_HUD_OVERLAY=true',
    '--dart-define=FLUXIDI_NAV_HIDE_MAPBOX_TAXI_MARKER_WITH_DRIVER_HUD=true',
    '--dart-define=FLUXIDI_NAV_DRIVER_COCKPIT_CAMERA=true',
    '--dart-define=FLUXIDI_NAV_DRIVER_COCKPIT_CAMERA_CONTROLS=true',
    '--dart-define=FLUXIDI_NAV_3D_COCKPIT_SCENE=true',
    '--dart-define=FLUXIDI_NAV_LANE_GUIDANCE=true',
    '--dart-define=LEARNING_BASE_URL=https://fluxidi-learning-api.fluxidi.workers.dev',
    "--dart-define=MAPBOX_TOKEN=$($env:MAPBOX_TOKEN)",
    "--dart-define=WORKER_BASE_URL=$($env:WORKER_BASE_URL)",
    "--dart-define=BOOKING_BASE_URL=$($env:BOOKING_BASE_URL)",

    # Play-only: disable company SaaS Mollie purchase/upgrade/add-on checkout.
    '--dart-define=FLUXIDI_PLAY_DISTRIBUTION=true'
)

$dartDefineKeys = @(
    $flutterArguments |
        Where-Object { $_ -like '--dart-define=*' } |
        ForEach-Object {
            $_ -replace '^--dart-define=([^=]+)=.*$', '$1'
        }
)

Write-Host "dart_define_key_count=$($dartDefineKeys.Count)"
Write-Host 'dart_define_keys (values hidden):'
$dartDefineKeys | ForEach-Object { Write-Host "  $_" }

if ($dartDefineKeys -notcontains 'FLUXIDI_PLAY_DISTRIBUTION') {
    throw 'FLUXIDI_PLAY_DISTRIBUTION dart-define is required for Play AAB'
}

$forbidden = @(
    $flutterArguments |
        Where-Object { $_ -match 'ADMIN[_-]?TOKEN|LEARNING_SERVICE_TOKEN' }
)
if ($forbidden.Count -gt 0) {
    throw 'Forbidden token present in Flutter build arguments'
}

Write-Host 'Building Play release appbundle…'
& flutter @flutterArguments
Assert-LastExitCode -Step 'flutter build appbundle'

$aab = 'build/app/outputs/bundle/release/app-release.aab'
if (-not (Test-Path -LiteralPath $aab)) {
    throw "Expected AAB missing: $aab"
}

$hash = (Get-FileHash -LiteralPath $aab -Algorithm SHA256).Hash.ToLowerInvariant()
$size = (Get-Item -LiteralPath $aab).Length
Write-Host "AAB=$aab"
Write-Host "AAB_BYTES=$size"
Write-Host "AAB_SHA256=$hash"
Write-Host 'PLAY_SAAS_CHECKOUT=disabled'
Write-Host 'RIDE_PAYMENTS=preserved'

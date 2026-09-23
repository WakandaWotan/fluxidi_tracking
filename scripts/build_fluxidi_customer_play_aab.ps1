# Fluxidi Klanten — signed Play AAB (internal testing identity).
#
# Lasting applicationId: com.fluxidi.customer
# Local development APK identity com.fluxidi.customer.dev is unchanged.
# Never builds or uploads com.fluxidi.tracking.

$ErrorActionPreference = 'Stop'

function Assert-LastExitCode([string]$Step) {
    if ($LASTEXITCODE -ne 0) {
        throw "$Step failed with exit code $LASTEXITCODE"
    }
}

$repoRoot = Split-Path -Parent $PSScriptRoot
$appDir = Join-Path $repoRoot 'apps\fluxidi_customer'
Set-Location -LiteralPath $appDir

$envFile = "$env:USERPROFILE\.fluxidi\fluxidi-dev-env.ps1"
if (-not (Test-Path -LiteralPath $envFile)) {
    throw "Fluxidi-omgevingsbestand ontbreekt: $envFile"
}
. $envFile

Remove-Item -Path Env:ADMIN_TOKEN -ErrorAction SilentlyContinue
Remove-Item -Path Env:LEARNING_SERVICE_TOKEN -ErrorAction SilentlyContinue

foreach ($name in @('MAPBOX_TOKEN', 'WORKER_BASE_URL', 'BOOKING_BASE_URL')) {
    $value = [Environment]::GetEnvironmentVariable($name, 'Process')
    if ([string]::IsNullOrWhiteSpace($value)) { throw "$name ontbreekt of is leeg" }
    Write-Host "$name aanwezig (waarde verborgen)"
}

if (-not (Test-Path -LiteralPath (Join-Path $appDir 'android\key.properties'))) {
    throw 'apps/fluxidi_customer/android/key.properties ontbreekt'
}

$env:FLUXIDI_CUSTOMER_PLAY = 'true'

& dart run tool/unused_bridge_package_assets_check.dart
Assert-LastExitCode -Step 'unused_bridge_package_assets_check'

& dart run tool/sync_bridge_assets.dart
Assert-LastExitCode -Step 'sync_bridge_assets'

$flutterArguments = @(
    'build',
    'appbundle',
    '--release',
    '--build-name=1.0.4',
    '--build-number=5',
    "-PFLUXIDI_CUSTOMER_PLAY=true",
    "--dart-define=FLUXIDI_CUSTOMER_PLAY=true",
    "--dart-define=FLUXIDI_CUSTOMER_APP_NAME=Fluxidi Klanten",
    "--dart-define=FLUXIDI_CUSTOMER_ENV_LABEL=",
    "--dart-define=FLUXIDI_CUSTOMER_APPLICATION_ID=com.fluxidi.customer",
    "--dart-define=FLUXIDI_CUSTOMER_DEEP_LINK_SCHEME=fluxidicustomer",
    "--dart-define=MAPBOX_TOKEN=$($env:MAPBOX_TOKEN)",
    "--dart-define=WORKER_BASE_URL=$($env:WORKER_BASE_URL)",
    "--dart-define=BOOKING_BASE_URL=$($env:BOOKING_BASE_URL)"
)

Write-Host 'Building Fluxidi Klanten Play appbundle…'
& flutter @flutterArguments
Assert-LastExitCode -Step 'flutter build appbundle --release'

$aab = Join-Path $appDir 'build\app\outputs\bundle\release\app-release.aab'
if (-not (Test-Path -LiteralPath $aab)) { throw "AAB ontbreekt: $aab" }
$hash = (Get-FileHash -LiteralPath $aab -Algorithm SHA256).Hash.ToLowerInvariant()
$size = (Get-Item -LiteralPath $aab).Length
Write-Host "AAB=$aab"
Write-Host "AAB_BYTES=$size"
Write-Host "AAB_MB=$([math]::Round($size / 1MB, 1))"
Write-Host "AAB_SHA256=$hash"
Write-Host 'PLAY_PACKAGE=com.fluxidi.customer'
Write-Host 'TRACKING_PACKAGE=untouched'

& dart run tool/verify_customer_release_assets.dart $aab
Assert-LastExitCode -Step 'verify_customer_release_assets'

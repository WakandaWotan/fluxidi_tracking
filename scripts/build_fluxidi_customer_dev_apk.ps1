# ============================================================================
# Fluxidi Customer Dev — development APK for the tablet
#
# Builds apps/fluxidi_customer and installs it NEXT TO the existing Fluxidi app.
# The application id is com.fluxidi.customer.dev, so com.fluxidi.tracking is
# never touched, replaced or uninstalled.
#
# The build is signed with the debug key on purpose: this is a development
# identity, not a Play build. No release keystore is used or required.
# ============================================================================

param(
    [string]$Device = 'R52Y808CN2M',
    [ValidateSet('release', 'debug', 'profile')]
    [string]$BuildMode = 'release',
    [switch]$SkipInstall
)

$ErrorActionPreference = 'Stop'

function Assert-LastExitCode {
    param([Parameter(Mandatory = $true)][string]$Step)
    if ($LASTEXITCODE -ne 0) { throw "${Step} is mislukt (exitcode $LASTEXITCODE)" }
}

$repoRoot = Split-Path -Parent $PSScriptRoot
$appDir = Join-Path $repoRoot 'apps\fluxidi_customer'
$adb = "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe"
$applicationId = 'com.fluxidi.customer.dev'
$existingApplicationId = 'com.fluxidi.tracking'

if (-not (Test-Path -LiteralPath $appDir)) { throw "App ontbreekt: $appDir" }

Set-Location -LiteralPath $appDir

# --- Secrets from the local, gitignored environment file ---
$envFile = "$env:USERPROFILE\.fluxidi\fluxidi-dev-env.ps1"
if (-not (Test-Path -LiteralPath $envFile)) {
    throw "Fluxidi-omgevingsbestand ontbreekt: $envFile"
}
. $envFile

# Service secrets never belong in an app build.
Remove-Item -Path Env:ADMIN_TOKEN -ErrorAction SilentlyContinue
Remove-Item -Path Env:LEARNING_SERVICE_TOKEN -ErrorAction SilentlyContinue

foreach ($name in @('MAPBOX_TOKEN', 'WORKER_BASE_URL', 'BOOKING_BASE_URL')) {
    $value = [Environment]::GetEnvironmentVariable($name, 'Process')
    if ([string]::IsNullOrWhiteSpace($value)) { throw "$name ontbreekt of is leeg" }
    Write-Host "$name aanwezig (waarde verborgen)"
}

# --- Bridge assets: the customer screens load 'assets/fluxidi/...' keys ---
& dart run tool/sync_bridge_assets.dart
Assert-LastExitCode -Step 'sync_bridge_assets'

& flutter pub get
Assert-LastExitCode -Step 'flutter pub get'

# The vendored Mapbox plugin must win here too; pub ignores a dependency's own
# dependency_overrides, so only this app's block decides.
$packageConfig = '.\.dart_tool\package_config.json'
if (-not (Test-Path -LiteralPath $packageConfig)) {
    throw 'package_config.json ontbreekt na flutter pub get'
}
if (-not ((Get-Content -LiteralPath $packageConfig -Raw) -match 'third_party[/\\]mapbox_maps_flutter')) {
    throw 'Lokale mapbox_maps_flutter override is niet actief'
}
Write-Host 'mapbox_override_active=True'

$flutterArguments = @(
    'build', 'apk', "--$BuildMode",
    "--dart-define=MAPBOX_TOKEN=$($env:MAPBOX_TOKEN)",
    "--dart-define=WORKER_BASE_URL=$($env:WORKER_BASE_URL)",
    "--dart-define=BOOKING_BASE_URL=$($env:BOOKING_BASE_URL)"
)

& flutter @flutterArguments
Assert-LastExitCode -Step "flutter build apk --$BuildMode"

$apk = Join-Path $appDir "build\app\outputs\flutter-apk\app-$BuildMode.apk"
if (-not (Test-Path -LiteralPath $apk)) { throw "APK niet gevonden: $apk" }
Write-Host "apk=$apk"
Write-Host ("apk_mb={0:N1}" -f ((Get-Item $apk).Length / 1MB))

if ($SkipInstall) { return }

if (-not (Test-Path -LiteralPath $adb)) { throw "ADB werd niet gevonden: $adb" }

$state = (& $adb -s $Device get-state 2>$null | Out-String).Trim()
if ($state -ne 'device') { throw "Toestel $Device is niet beschikbaar. Status: '$state'" }

# Installs alongside; -r only replaces this app's own previous build.
& $adb -s $Device install -r $apk
Assert-LastExitCode -Step 'adb install'

$installed = (& $adb -s $Device shell pm list packages $existingApplicationId | Out-String).Trim()
if ($installed -notmatch [regex]::Escape($existingApplicationId)) {
    Write-Host "LET OP: $existingApplicationId staat niet op dit toestel." -ForegroundColor Yellow
} else {
    Write-Host "bestaande_app_intact=$existingApplicationId" -ForegroundColor Green
}

Write-Host "geinstalleerd=$applicationId" -ForegroundColor Green
Write-Host 'Start de app via het icoon "Fluxidi Customer Dev".'

Set-Location -LiteralPath "C:\_flutter_work\fluxidi_tracking"

$ErrorActionPreference = "Stop"

Write-Host ""
Write-Host "============================================================" -ForegroundColor DarkCyan
Write-Host " FLUXIDI TABLET - ANDROID NATIVE FOLLOWPUCK PHASE 2A" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor DarkCyan
Write-Host ""

# ------------------------------------------------------------
# Git-status van de exacte code die zal worden gebouwd
# ------------------------------------------------------------

Write-Host "Controleer huidige Git-versie en lokale WIP..." -ForegroundColor DarkYellow
Write-Host ""

$gitCommand = Get-Command git -ErrorAction SilentlyContinue

if ($null -eq $gitCommand) {
  throw "Git is niet beschikbaar in PowerShell."
}

$insideGitRepository = (& git rev-parse --is-inside-work-tree 2>$null).Trim()

if ($insideGitRepository -ne "true") {
  throw "C:\_flutter_work\fluxidi_tracking is geen geldige Git-repository."
}

$currentBranch = (& git branch --show-current).Trim()
$currentCommit = (& git rev-parse --short HEAD).Trim()
$currentCommitFull = (& git rev-parse HEAD).Trim()

Write-Host "Git branch : $currentBranch" -ForegroundColor Cyan
Write-Host "Git commit : $currentCommit" -ForegroundColor Cyan
Write-Host "Full HEAD  : $currentCommitFull" -ForegroundColor DarkGray
Write-Host ""

$gitStatus = @(& git status --short)

if ($gitStatus.Count -eq 0) {
  Write-Host "Werkmap is volledig clean." -ForegroundColor Green
}
else {
  Write-Host "Lokale wijzigingen die OOK meegebouwd worden:" -ForegroundColor Yellow
  Write-Host ""

  foreach ($statusLine in $gitStatus) {
    Write-Host "  $statusLine" -ForegroundColor Yellow
  }

  Write-Host ""
  Write-Host "LET OP: flutter run bouwt de huidige lokale werkmap," -ForegroundColor DarkYellow
  Write-Host "dus ook bovenstaande niet-gecommitte WIP." -ForegroundColor DarkYellow
}

Write-Host ""
Write-Host "Laatste commit:" -ForegroundColor Cyan
& git log -1 --oneline

if ($LASTEXITCODE -ne 0) {
  throw "Git kon de laatste commit niet uitlezen."
}

Write-Host ""

# Controleer of de P2C lane-hardening in deze HEAD aanwezig is.
$requiredLaneCommit = "cf42e9b"

& git merge-base --is-ancestor $requiredLaneCommit HEAD 2>$null
$laneCommitPresent = ($LASTEXITCODE -eq 0)

if ($laneCommitPresent) {
  Write-Host "P2C-lanecommit $requiredLaneCommit is aanwezig." -ForegroundColor Green
}
else {
  throw "P2C-lanecommit $requiredLaneCommit ontbreekt in deze HEAD. Tablet-fieldbuild afgebroken."
}

Write-Host ""

# ------------------------------------------------------------
# Controleer of de vereiste Phase 2A-bestanden aanwezig zijn
# ------------------------------------------------------------

$requiredPhase2AFiles = @(
  ".\third_party\mapbox_maps_flutter\pubspec.yaml",
  ".\third_party\mapbox_maps_flutter\PATCHES.md",
  ".\pigeons\native_follow.dart",
  ".\lib\navigation\native_follow\pigeon_native_follow.g.dart",
  ".\lib\navigation\native_follow\native_follow_controller.dart",
  ".\lib\navigation\native_follow\native_follow_vehicle_calibration.dart",
  ".\android\app\src\main\kotlin\com\fluxidi\tracking\nativefollow\FluxidiNativeFollowManager.kt",
  ".\android\app\src\main\kotlin\com\fluxidi\tracking\nativefollow\FluxidiRouteSnappedLocationProvider.kt",
  ".\android\app\src\main\kotlin\com\fluxidi\tracking\nativefollow\FluxidiNativeFollowPlugin.kt"
)

foreach ($file in $requiredPhase2AFiles) {
  if (-not (Test-Path -LiteralPath $file)) {
    throw "Vereist Phase 2A-bestand ontbreekt: $file"
  }
}

Write-Host "Phase 2A Native FollowPuck-bronnen gevonden." -ForegroundColor Green

# ------------------------------------------------------------
# Stop mogelijke Flutter/Android build- en device-locks
# ------------------------------------------------------------

Write-Host ""
Write-Host "Stop Java-, Dart- en ADB-processen..." -ForegroundColor DarkYellow

$processNames = @(
  "java",
  "dart",
  "adb"
)

foreach ($processName in $processNames) {
  $runningProcesses = @(
    Get-Process -Name $processName -ErrorAction SilentlyContinue
  )

  if ($runningProcesses.Count -gt 0) {
    $runningProcesses |
      Stop-Process -Force -ErrorAction SilentlyContinue

    Write-Host "  $processName gestopt." -ForegroundColor DarkGray
  }
  else {
    Write-Host "  $processName was niet actief." -ForegroundColor DarkGray
  }
}

Start-Sleep -Seconds 2

# ------------------------------------------------------------
# Clean rebuild
# ------------------------------------------------------------

Write-Host ""
Write-Host "Verwijder gegenereerde buildmap..." -ForegroundColor DarkYellow

if (Test-Path -LiteralPath ".\build") {
  Remove-Item -LiteralPath ".\build" -Recurse -Force
}

Write-Host "Flutter clean..." -ForegroundColor DarkYellow

flutter clean

if ($LASTEXITCODE -ne 0) {
  throw "flutter clean is mislukt met foutcode $LASTEXITCODE"
}

Write-Host "Flutter pub get..." -ForegroundColor DarkYellow

flutter pub get

if ($LASTEXITCODE -ne 0) {
  throw "flutter pub get is mislukt met foutcode $LASTEXITCODE"
}

# ------------------------------------------------------------
# Controleer of de lokale Mapbox-pluginoverride actief is
# ------------------------------------------------------------

$packageConfig = ".\.dart_tool\package_config.json"

if (-not (Test-Path -LiteralPath $packageConfig)) {
  throw "Dart package_config ontbreekt na flutter pub get"
}

$packageConfigContent = Get-Content -LiteralPath $packageConfig -Raw

if ($packageConfigContent -notmatch "third_party[/\\]mapbox_maps_flutter") {
  throw "De lokale mapbox_maps_flutter Phase 2A-override lijkt niet actief te zijn"
}

Write-Host "Lokale Mapbox Flutter 2.18.0-override is actief." -ForegroundColor Green

# ------------------------------------------------------------
# Load Fluxidi dev secrets/env
# ------------------------------------------------------------

$envFile = "$env:USERPROFILE\.fluxidi\fluxidi-dev-env.ps1"

if (-not (Test-Path -LiteralPath $envFile)) {
  throw "Fluxidi env-bestand ontbreekt: $envFile"
}

. $envFile

# ------------------------------------------------------------
# Validate required tokens and URLs
# ------------------------------------------------------------

$requiredEnvironmentVariables = @(
  "MAPBOX_TOKEN",
  "WORKER_BASE_URL",
  "BOOKING_BASE_URL",
  "LEARNING_SERVICE_TOKEN"
)

foreach ($name in $requiredEnvironmentVariables) {
  $value = [Environment]::GetEnvironmentVariable(
    $name,
    [EnvironmentVariableTarget]::Process
  )

  if ([string]::IsNullOrWhiteSpace($value)) {
    throw "$name ontbreekt of is leeg"
  }
}

Write-Host ""
Write-Host "Fluxidi dev environment geladen." -ForegroundColor Green
Write-Host "MAPBOX_TOKEN length: $($env:MAPBOX_TOKEN.Length)"
Write-Host "LEARNING_SERVICE_TOKEN length: $($env:LEARNING_SERVICE_TOKEN.Length)"

# ------------------------------------------------------------
# Android tablet setup
# ------------------------------------------------------------

$adb = "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe"
$device = "R52Y808CN2M"

if (-not (Test-Path -LiteralPath $adb)) {
  throw "ADB niet gevonden: $adb"
}

Write-Host ""
Write-Host "Start ADB-server..." -ForegroundColor DarkYellow

& $adb start-server

if ($LASTEXITCODE -ne 0) {
  throw "ADB-server kon niet worden gestart"
}

Write-Host ""
Write-Host "Verbonden Android-apparaten:" -ForegroundColor Cyan

& $adb devices

if ($LASTEXITCODE -ne 0) {
  throw "ADB kon de apparatenlijst niet ophalen"
}

$deviceState = (& $adb -s $device get-state 2>$null).Trim()

if ($deviceState -ne "device") {
  throw "Tablet $device is niet correct verbonden. Huidige status: '$deviceState'"
}

Write-Host "Tablet $device is correct verbonden." -ForegroundColor Green

# Maak logcat leeg voor deze specifieke Phase 2A-test.
& $adb -s $device logcat -c

if ($LASTEXITCODE -ne 0) {
  throw "Logcat kon niet worden leeggemaakt"
}

Write-Host "Logcat werd leeggemaakt voor deze test." -ForegroundColor Green

# ------------------------------------------------------------
# Testinstructies
# ------------------------------------------------------------

Write-Host ""
Write-Host "============================================================" -ForegroundColor DarkCyan
Write-Host " NATIVE FOLLOWPUCK + LANE GUIDANCE ZIJN OP DE TABLET INGESCHAKELD" -ForegroundColor Green
Write-Host "============================================================" -ForegroundColor DarkCyan
Write-Host ""

Write-Host "Test de navigatiemarker op ELKE kaartstijl (Licht/Donker/3D-gebouwen/Satelliet)." -ForegroundColor Yellow
Write-Host "Kies de marker: Auto of Pijl. Standaard is Auto." -ForegroundColor Yellow
Write-Host "Wissel tijdens navigatie Auto <-> Pijl en controleer dat het meteen wisselt." -ForegroundColor Yellow
Write-Host ""

Write-Host "Controleer voor vertrek:" -ForegroundColor Cyan
Write-Host "  1. De app start zonder crash."
Write-Host "  2. Er is maximaal een marker zichtbaar (geen native puck eronder)."
Write-Host "  3. Auto werkt op Licht, Donker, 3D-gebouwen en Satelliet."
Write-Host "  4. Pijl werkt op Licht, Donker, 3D-gebouwen en Satelliet."
Write-Host "  5. Wissel Auto <-> Pijl: geen dubbele marker, geen lege toestand."
Write-Host "  6. Kaartstijlwissel behoudt de gekozen marker (Auto/Pijl)."
Write-Host "  7. Marker draait koerscorrect mee met de routecourse."
Write-Host "  8. In Street Level staan Auto en Pijl net boven de KPI-tellers (portrait en landscape)."
Write-Host "  9. View + en View - werken; camera hervat volgen na actie."
Write-Host " 10. De manoeuvrebanner verschijnt niet te vroeg bij vertrek."
Write-Host " 11. Bannertekst en manoeuvrepijl horen bij dezelfde manoeuvre."
Write-Host " 12. Op een gewone eenbaansweg verschijnt geen lane-rij."
Write-Host " 13. Bij een duidelijke splitsing klopt het aantal lane-kolommen exact."
Write-Host " 14. Een oude lane-rij verdwijnt bij stapwissel of reroute."
Write-Host ""

Write-Host "Er wordt géén 3D-voertuig, GLB of ModelLayer meer geladen tijdens navigatie." -ForegroundColor Cyan
Write-Host "De 3D-gebouwenkaart (Mapbox Standard) blijft gewoon beschikbaar." -ForegroundColor Cyan
Write-Host ""
Write-Host "Lane guidance is voor deze tablet-fieldbuild ingeschakeld." -ForegroundColor Green
Write-Host "Normale builds zonder deze dart-define blijven standaard uit." -ForegroundColor DarkYellow
Write-Host ""

# ------------------------------------------------------------
# Deze build activeert:
#
# - Driver HUD overlay (2D navigatiemarker: Auto of Pijl)
# - cockpitcamera en View +/- bediening
# - Mapbox Standard 3D-gebouwenkaart (kaartstijl, geen 3D-voertuig)
# - Fluxidi route-snapped/predicted positie
# - actieve GPS-instellingen van Phase 1
# - adaptive Dart-camera-follow (routecourse als camerabearing)
# - reroute-stabilisatie
# - uitgestelde achtergrondtaken tijdens actieve navigatie
# - P1/P1B Mapbox-bannerownership en afstandsactivatie
# - P2B/P2C veilige lane-resolutie, semantiek en 1-op-1 kolomweergave
#
# NAV-VEHICLE-MODE-CAR-ARROW-1: de experimentele 3D-voertuigen zijn verwijderd.
# Er wordt geen GLB, ModelLayer of native LocationPuck3D meer geladen. De
# marker is altijd de lichte 2D HUD (Auto/Pijl) en is de enige zichtbare
# marker; de native FollowPuck staat uit zodat er nooit een puck onder de
# custom marker verschijnt.
#
# Lane guidance is alleen voor deze tablet-fieldbuild ingeschakeld via:
# FLUXIDI_NAV_LANE_GUIDANCE=true
# ------------------------------------------------------------

Write-Host "Start Flutter in profile mode..." -ForegroundColor Green
Write-Host ""

$flutterArguments = @(
  "run",
  "--profile",
  "--no-enable-impeller",
  "-d",
  $device,
  "--dart-define=NAV_COMPLEXITY_CLOUD_UPLOAD=true",
  "--dart-define=NAV_COMPLEXITY_FETCH_ADVISORY_RULES=true",
  "--dart-define=FLUXIDI_NAV_DRIVER_HUD_OVERLAY=true",
  "--dart-define=FLUXIDI_NAV_HIDE_MAPBOX_TAXI_MARKER_WITH_DRIVER_HUD=true",
  "--dart-define=FLUXIDI_NAV_DRIVER_COCKPIT_CAMERA=true",
  "--dart-define=FLUXIDI_NAV_DRIVER_COCKPIT_CAMERA_CONTROLS=true",
  # NAV-3D-BUILDINGS-STYLE-RESTORE-1: dit is de KAARTSTIJL-define (Mapbox
  # Standard / 3D-gebouwen + kaartstijlselector Licht/Donker/3D/Satelliet),
  # GEEN 3D-voertuigdefine. Ze werd bij NAV-VEHICLE-MODE-CAR-ARROW-1 per
  # ongeluk mee verwijderd, waardoor 3D uit de stijlselector verdween.
  "--dart-define=FLUXIDI_NAV_3D_COCKPIT_SCENE=true",
  # NAV-VEHICLE-MODE-CAR-ARROW-1: 3D-voertuig + native 3D-puck defines
  # verwijderd. Marker is de 2D HUD (Auto/Pijl); 3D-gebouwenkaart blijft.
  "--dart-define=FLUXIDI_NAV_LANE_GUIDANCE=true",
  "--dart-define=LEARNING_BASE_URL=https://fluxidi-learning-api.fluxidi.workers.dev",
  "--dart-define=LEARNING_SERVICE_TOKEN=$($env:LEARNING_SERVICE_TOKEN)",
  "--dart-define=MAPBOX_TOKEN=$($env:MAPBOX_TOKEN)",
  "--dart-define=WORKER_BASE_URL=$($env:WORKER_BASE_URL)",
  "--dart-define=BOOKING_BASE_URL=$($env:BOOKING_BASE_URL)"
)

$requiredLaneArgument = "--dart-define=FLUXIDI_NAV_LANE_GUIDANCE=true"

if ($flutterArguments -notcontains $requiredLaneArgument) {
  throw "Lane-guidanceargument ontbreekt. Flutter run wordt niet gestart."
}

Write-Host "Lane-guidanceargument gecontroleerd: actief voor deze tablet-fieldbuild." -ForegroundColor Green
Write-Host ""

flutter @flutterArguments

if ($LASTEXITCODE -ne 0) {
  throw "flutter run is afgesloten met foutcode $LASTEXITCODE"
}

Write-Host ""
Write-Host "Flutter run is normaal afgesloten." -ForegroundColor Green
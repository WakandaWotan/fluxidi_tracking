# ============================================================================
# FLUXIDI FIELD BUILD — Tablet
# Exact commit: a4f884608e3ee6683a16baed00e214a24dc38311
# Clean integration worktree. Dirty hoofdrepository blijft onaangeraakt.
# Exact 12 dart-defines, NO ADMIN_TOKEN, NO LEARNING_SERVICE_TOKEN.
#
# PIN NOTE: TABLET-PIN-GOOGLE-MAPS-PIP-RELEASE-1
# App head adds Google Maps direct launch + Fluxidi PiP meter as a second
# NAV option (native Intent, no browser chooser). Theme/Billit/PNG/owner
# gates remain. On HEAD mismatch the script checks out $requiredHead in
# place (or recreates).
# ============================================================================

$ErrorActionPreference = 'Stop'

# --- Vaste instellingen ---
$repo         = 'C:\_flutter_work\fluxidi_tracking'
$worktree     = 'C:\_flutter_work\fluxidi_tracking_full_integration_20260805'
$device       = 'R52Y808CN2M'
$adb          = "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe"
$requiredHead = 'a4f884608e3ee6683a16baed00e214a24dc38311'
$branch       = 'release/full-tablet-integration-20260805'

function Assert-LastExitCode {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Step
    )

    if ($LASTEXITCODE -ne 0) {
        throw "${Step} is mislukt (exitcode $LASTEXITCODE)"
    }
}

function Assert-CleanWorktree {
    param(
        [Parameter(Mandatory = $true)]
        [string]$GateName
    )

    $status = @(& git status --short)
    Assert-LastExitCode -Step "git status bij ${GateName}"

    Write-Host "${GateName}_status_lines=$($status.Count)"

    if ($status.Count -gt 0) {
        Write-Host "${GateName} FAILED - worktree is niet clean:" `
            -ForegroundColor Red

        $status | ForEach-Object {
            Write-Host "  $_" -ForegroundColor Red
        }

        throw "${GateName}: worktree is niet clean"
    }

    Write-Host "${GateName}_clean=True" -ForegroundColor Green
}

function Assert-FreeDiskSpace {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [int]$MinimumGiB = 12
    )

    $root = [System.IO.Path]::GetPathRoot($Path)
    $drive = [System.IO.DriveInfo]::new($root)
    $freeGiB = [math]::Round($drive.AvailableFreeSpace / 1GB, 2)

    Write-Host "disk_root=$root"
    Write-Host "disk_free_gib=$freeGiB"
    Write-Host "disk_required_gib=$MinimumGiB"

    if ($drive.AvailableFreeSpace -lt ($MinimumGiB * 1GB)) {
        throw (
            "Onvoldoende vrije schijfruimte op $root. " +
            "Vrij: $freeGiB GiB; vereist: minstens $MinimumGiB GiB. " +
            "Maak ruimte vrij en start hetzelfde script opnieuw."
        )
    }

    Write-Host 'disk_space_gate=True' -ForegroundColor Green
}

# ============================================================================
# SCHONE WORKTREE VOORBEREIDEN
# ============================================================================

if (-not (Test-Path -LiteralPath $repo)) {
    throw "Hoofdrepository ontbreekt: $repo"
}

function Ensure-PinnedTabletWorktree {
    Set-Location -LiteralPath $repo

    & git cat-file -e $requiredHead 2>$null
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Commit niet lokaal gevonden; branch wordt opgehaald..."
        & git fetch origin $branch
        Assert-LastExitCode -Step 'git fetch'
    }

    if (-not (Test-Path -LiteralPath $worktree)) {
        Write-Host "Clean worktree bestaat nog niet en wordt aangemaakt..."
        & git worktree add --detach $worktree $requiredHead
        Assert-LastExitCode -Step 'git worktree add'
        return
    }

    Set-Location -LiteralPath $worktree
    $insideWorktree = (& git rev-parse --is-inside-work-tree).Trim()
    Assert-LastExitCode -Step 'git rev-parse --is-inside-work-tree'
    if ($insideWorktree -ne 'true') {
        throw "Pad is geen geldige Git-worktree: $worktree"
    }

    $head = (& git rev-parse HEAD).Trim()
    Assert-LastExitCode -Step 'git rev-parse HEAD'
    Write-Host "worktree_head_before=$head"

    if ($head -eq $requiredHead) {
        return
    }

    # Never silently keep an older detached pin (root cause of stale Chiron UI).
    # Prefer in-place checkout: Windows often locks the worktree directory
    # (Gradle/Flutter/IDE) so `git worktree remove` fails with Permission denied.
    Write-Host "HEAD mismatch: checking out required pin $requiredHead in place" `
        -ForegroundColor Yellow
    Set-Location -LiteralPath $worktree
    & git checkout --detach $requiredHead
    if ($LASTEXITCODE -ne 0) {
        Write-Host "checkout failed; attempting force recreate..." -ForegroundColor Yellow
        Set-Location -LiteralPath $repo
        & git worktree remove --force $worktree
        if ($LASTEXITCODE -ne 0) {
            throw (
                "Kan worktree niet bijwerken naar $requiredHead. " +
                "Sluit Gradle/Flutter/IDE-processen die $worktree vasthouden " +
                "en start het script opnieuw."
            )
        }
        & git worktree add --detach $worktree $requiredHead
        Assert-LastExitCode -Step 'git worktree add'
        return
    }
    & git reset --hard $requiredHead
    Assert-LastExitCode -Step 'git reset --hard requiredHead'
    & git clean -fd
    Assert-LastExitCode -Step 'git clean -fd'
}

Ensure-PinnedTabletWorktree

Set-Location -LiteralPath $worktree

$insideWorktree = (& git rev-parse --is-inside-work-tree).Trim()
Assert-LastExitCode -Step 'git rev-parse --is-inside-work-tree'

if ($insideWorktree -ne 'true') {
    throw "Pad is geen geldige Git-worktree: $worktree"
}

# --- Exacte beveiligde commit controleren ---
$head = (& git rev-parse HEAD).Trim()
Assert-LastExitCode -Step 'git rev-parse HEAD'

Write-Host "worktree_head=$head"

if ($head -ne $requiredHead) {
    throw "HEAD mismatch after ensure: gevonden $head, verwacht $requiredHead"
}

# --- FULL-PRODUCT-PLUS-PNG-NAV-20260805 source gates ---
$requiredSubject = (& git log -1 --format=%s $requiredHead).Trim()
Assert-LastExitCode -Step 'git log required subject'

$themeButtonPath = '.\lib\widgets\business_theme_cycle_button.dart'
$themeCyclePath = '.\lib\business_theme_cycle.dart'
$signResolverPath = '.\lib\navigation\presentation\nav_sign_resolver.dart'
$maneuverOwnerPath = '.\lib\navigation\nav_engine\nav_maneuver_owner.dart'
$bookingsDocsPath = '.\lib\main_parts\company_booking_documents_section.dart'

if (-not (Test-Path -LiteralPath $themeButtonPath)) {
    throw "BusinessThemeCycleButton ontbreekt: $themeButtonPath"
}
if (-not (Test-Path -LiteralPath $themeCyclePath)) {
    throw "business_theme_cycle.dart ontbreekt: $themeCyclePath"
}
if (-not (Test-Path -LiteralPath $signResolverPath)) {
    throw "nav_sign_resolver.dart ontbreekt: $signResolverPath"
}
if (-not (Test-Path -LiteralPath $maneuverOwnerPath)) {
    throw "nav_maneuver_owner.dart ontbreekt: $maneuverOwnerPath"
}

$themeCycleRaw = Get-Content -LiteralPath $themeCyclePath -Raw
$presetCount = @(
    'executiveGold',
    'corporateBlue',
    'cleanProfessional',
    'emeraldIvory',
    'fluxidiNeonRush'
) | Where-Object { $themeCycleRaw -match $_ } | Measure-Object | Select-Object -ExpandProperty Count
if ($presetCount -ne 5) {
    throw "theme_preset_count=$presetCount (verwacht 5)"
}

$bookingsRaw = Get-Content -LiteralPath $bookingsDocsPath -Raw
if ($bookingsRaw -notmatch 'billit_export|BillitExport|_BillitExportMetadata') {
    throw "Billit/documentactie ontbreekt in company_booking_documents_section.dart"
}

$pngCount = @(
    Get-ChildItem -LiteralPath '.\assets\fluxidi_navigation_signs_v3\png' `
        -Recurse -Filter '*.png' -File
).Count
if ($pngCount -ne 136) {
    throw "nav_sign_png_count=$pngCount (verwacht 136)"
}

$langCount = @(
    'nl', 'en', 'fr', 'es'
) | Where-Object {
    Test-Path -LiteralPath ".\assets\fluxidi_navigation_signs_v3\png\$_"
} | Measure-Object | Select-Object -ExpandProperty Count
if ($langCount -ne 4) {
    throw "nav_sign_languages=$langCount (verwacht 4)"
}

Write-Host "required_app_head=$requiredHead"
Write-Host "required_app_subject=$requiredSubject"
Write-Host 'theme_cycle_present=True'
Write-Host "theme_preset_count=$presetCount"
Write-Host 'business_billit_action_present=True'
Write-Host "nav_sign_png_count=$pngCount"
Write-Host "nav_sign_languages=$langCount"
Write-Host 'nav_maneuver_owner_present=True'
$brandingLayoutPath = '.\lib\nearby\tablet_partner_branding_layout.dart'
if (-not (Test-Path -LiteralPath $brandingLayoutPath)) {
    throw "tablet_partner_branding_layout.dart ontbreekt: $brandingLayoutPath"
}
$brandingRaw = Get-Content -LiteralPath $brandingLayoutPath -Raw
if ($brandingRaw -notmatch 'isTabletPartnerBrandingLayout|PartnerBrandingLogoPlate') {
    throw 'Tablet partner branding helpers ontbreken'
}
Write-Host 'tablet_partner_branding_layout_present=True'
Write-Host "worktree_head=$head"


# --- Windows-regelovergangen neutraliseren zonder gedeelde Git-config te wijzigen ---
# Gebruik per commando tijdelijke instellingen. Dit vermijdt conflicten met
# C:\_flutter_work\fluxidi_tracking\.git\config.lock bij meerdere worktrees.
foreach ($path in @(
    'linux/flutter',
    'macos/Flutter',
    'windows/flutter'
)) {
    & git -c core.autocrlf=false -c core.eol=lf checkout HEAD -- $path 2>&1 |
        Out-Null
    Assert-LastExitCode -Step "git checkout $path"
}

# --- Native FollowPuck-bronnen controleren ---
$requiredNativeFiles = @(
    '.\third_party\mapbox_maps_flutter\pubspec.yaml',
    '.\third_party\mapbox_maps_flutter\PATCHES.md',
    '.\pigeons\native_follow.dart',
    '.\lib\navigation\native_follow\pigeon_native_follow.g.dart',
    '.\lib\navigation\native_follow\native_follow_controller.dart',
    '.\lib\navigation\native_follow\native_follow_vehicle_calibration.dart',
    '.\android\app\src\main\kotlin\com\fluxidi\tracking\nativefollow\FluxidiNativeFollowManager.kt',
    '.\android\app\src\main\kotlin\com\fluxidi\tracking\nativefollow\FluxidiRouteSnappedLocationProvider.kt',
    '.\android\app\src\main\kotlin\com\fluxidi\tracking\nativefollow\FluxidiNativeFollowPlugin.kt'
)

foreach ($file in $requiredNativeFiles) {
    if (-not (Test-Path -LiteralPath $file)) {
        throw "Vereiste Native FollowPuck-bron ontbreekt: $file"
    }
}

Write-Host 'native_followpuck_sources=all_present'

# ============================================================================
# GATE 1 — vóór Flutter clean/pub get
# ============================================================================

Assert-CleanWorktree -GateName 'gate_1'

# --- Blokkerende processen stoppen ---
foreach ($processName in @('java', 'dart', 'adb')) {
    Get-Process -Name $processName -ErrorAction SilentlyContinue |
        Stop-Process -Force -ErrorAction SilentlyContinue
}

Start-Sleep -Seconds 2

# --- Restanten van een eerdere mislukte build veilig verwijderen ---
if (Test-Path -LiteralPath '.\build') {
    Write-Host 'Verwijdert gedeeltelijke buildmap van deze worktree...'
    Remove-Item -LiteralPath '.\build' -Recurse -Force
}

if (Test-Path -LiteralPath '.\android\.gradle') {
    Write-Host 'Verwijdert lokale Android-Gradlecache van deze worktree...'
    Remove-Item -LiteralPath '.\android\.gradle' -Recurse -Force
}

# Een Fluxidi profile-build heeft ruime tijdelijke schijfruimte nodig.
Assert-FreeDiskSpace -Path $worktree

# --- Volledige schone Flutter-build voorbereiden ---
& flutter clean
Assert-LastExitCode -Step 'flutter clean'

& flutter pub get
Assert-LastExitCode -Step 'flutter pub get'

# --- Lokale Mapbox-override controleren ---
$packageConfig = '.\.dart_tool\package_config.json'

if (-not (Test-Path -LiteralPath $packageConfig)) {
    throw 'package_config.json ontbreekt na flutter pub get'
}

$mapboxOverrideActive = (
    Get-Content -LiteralPath $packageConfig -Raw
) -match 'third_party[/\\]mapbox_maps_flutter'

if (-not $mapboxOverrideActive) {
    throw 'Lokale mapbox_maps_flutter override is niet actief'
}

Write-Host 'mapbox_override_active=True'

# ============================================================================
# GATE 2 — na Flutter pub get
# ============================================================================

Assert-CleanWorktree -GateName 'gate_2'

# --- Fluxidi-omgeving laden ---
$envFile = "$env:USERPROFILE\.fluxidi\fluxidi-dev-env.ps1"

if (-not (Test-Path -LiteralPath $envFile)) {
    throw "Fluxidi-omgevingsbestand ontbreekt: $envFile"
}

. $envFile

# --- Geheime servicesleutels expliciet verwijderen ---
Remove-Item -Path Env:ADMIN_TOKEN -ErrorAction SilentlyContinue
Remove-Item -Path Env:LEARNING_SERVICE_TOKEN -ErrorAction SilentlyContinue

if ([Environment]::GetEnvironmentVariable('ADMIN_TOKEN', 'Process')) {
    throw 'ADMIN_TOKEN is nog aanwezig'
}

if ([Environment]::GetEnvironmentVariable(
    'LEARNING_SERVICE_TOKEN',
    'Process'
)) {
    throw 'LEARNING_SERVICE_TOKEN is nog aanwezig'
}

Write-Host 'ADMIN_TOKEN_scrubbed=True'
Write-Host 'LEARNING_SERVICE_TOKEN_scrubbed=True'

foreach ($variableName in @(
    'MAPBOX_TOKEN',
    'WORKER_BASE_URL',
    'BOOKING_BASE_URL'
)) {
    $value = [Environment]::GetEnvironmentVariable(
        $variableName,
        'Process'
    )

    if ([string]::IsNullOrWhiteSpace($value)) {
        throw "$variableName ontbreekt of is leeg"
    }

    Write-Host "$variableName present (waarde verborgen)"
}

# --- ADB en toestel controleren ---
if (-not (Test-Path -LiteralPath $adb)) {
    throw "ADB werd niet gevonden: $adb"
}

& $adb start-server | Out-Null
Assert-LastExitCode -Step 'adb start-server'

& $adb devices -l
Assert-LastExitCode -Step 'adb devices'

$state = (
    & $adb -s $device get-state 2>$null |
        Out-String
).Trim()

if ($state -ne 'device') {
    throw "Tablet $device is niet beschikbaar als device. Status: '$state'"
}

Write-Host "tablet=$device state=device"

& $adb -s $device logcat -c | Out-Null
Assert-LastExitCode -Step 'adb logcat -c'

Write-Host 'logcat_cleared=True'

# ============================================================================
# Exact 12 dart-defines
# ============================================================================

$flutterArguments = @(
    'run',
    '--profile',
    '--no-enable-impeller',
    '-d', $device,

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
    "--dart-define=BOOKING_BASE_URL=$($env:BOOKING_BASE_URL)"
)

$dartDefineKeys = @(
    $flutterArguments |
        Where-Object { $_ -like '--dart-define=*' } |
        ForEach-Object {
            $_ -replace '^--dart-define=([^=]+)=.*$', '$1'
        }
)

Write-Host ''
Write-Host "dart_define_key_count=$($dartDefineKeys.Count)"
Write-Host 'dart_define_keys (waarden verborgen):'

$dartDefineKeys | ForEach-Object {
    Write-Host "  $_"
}

if ($dartDefineKeys.Count -ne 12) {
    throw "Er moeten exact 12 dart-defines zijn; gevonden: $($dartDefineKeys.Count)"
}

$forbiddenArguments = @(
    $flutterArguments |
        Where-Object {
            $_ -match 'ADMIN[_-]?TOKEN|LEARNING_SERVICE_TOKEN'
        }
)

if ($forbiddenArguments.Count -gt 0) {
    throw 'Een verboden token zit in de Flutter-argumenten'
}

if ($flutterArguments -notcontains
    '--dart-define=FLUXIDI_NAV_LANE_GUIDANCE=true') {
    throw 'Lane-guidance dart-define ontbreekt'
}

Write-Host 'ADMIN_TOKEN_in_final_args=0'
Write-Host 'LEARNING_SERVICE_TOKEN_in_final_args=0'
Write-Host 'lane_guidance_argument=present'

# ============================================================================
# GATE 3 — onmiddellijk vóór flutter run
# ============================================================================

Assert-CleanWorktree -GateName 'gate_3'
Assert-FreeDiskSpace -Path $worktree

Write-Host ''
Write-Host 'Tablet wordt nu gebouwd, geïnstalleerd en gestart...'
Write-Host ''

& flutter @flutterArguments
Assert-LastExitCode -Step 'flutter run'
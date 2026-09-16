# One release APK for Xiaomi phone + Samsung tablet, same source as Windows.
# Points at production booking. No localhost, no demo token, no E2E, no AAB/Play.
# Inspects attached devices, then builds. Does not install or uninstall.

$ErrorActionPreference = 'Stop'
$repo = Split-Path $PSScriptRoot -Parent
$adb = Join-Path $env:LOCALAPPDATA 'Android\Sdk\platform-tools\adb.exe'
$outDir = Join-Path $repo '.qa-local\real-account'
$uploadProps = Join-Path $env:USERPROFILE '.fluxidi\fluxidi-upload-key.properties'
$androidProps = Join-Path $repo 'android\key.properties'
$devEnv = Join-Path $env:USERPROFILE '.fluxidi\fluxidi-dev-env.ps1'
$phoneSerial = 'SG7XLZ7TKRLZOJTG'
$tabletSerial = 'R52Y808CN2M'

New-Item -ItemType Directory -Force -Path $outDir | Out-Null
Set-Location -LiteralPath $repo

if (Test-Path -LiteralPath $devEnv) { . $devEnv }
Remove-Item -Path Env:ADMIN_TOKEN -ErrorAction SilentlyContinue
Remove-Item -Path Env:LEARNING_SERVICE_TOKEN -ErrorAction SilentlyContinue
Remove-Item -Path Env:COMPANY_SESSION_TOKEN -ErrorAction SilentlyContinue
Remove-Item -Path Env:BOOKING_BASE_URL -ErrorAction SilentlyContinue
Remove-Item -Path Env:FLUXIDI_E2E_TEST_TOKEN -ErrorAction SilentlyContinue

if (-not (Test-Path -LiteralPath $androidProps)) {
  if (-not (Test-Path -LiteralPath $uploadProps)) {
    throw "Upload key.properties missing: $uploadProps"
  }
  Copy-Item -LiteralPath $uploadProps -Destination $androidProps -Force
  Write-Host 'android/key.properties copied from Fluxidi upload key file (contents hidden)'
}

if ([string]::IsNullOrWhiteSpace($env:MAPBOX_TOKEN)) {
  throw 'MAPBOX_TOKEN ontbreekt. Verwachte bron: fluxidi-dev-env.ps1'
}

if (Test-Path -LiteralPath $adb) {
  & $adb start-server | Out-Null
  & $adb devices -l | Tee-Object -FilePath (Join-Path $outDir 'adb_devices.txt')
  foreach ($serial in @($phoneSerial, $tabletSerial)) {
    $state = (& $adb -s $serial get-state 2>$null | Out-String).Trim()
    $deviceLog = Join-Path $outDir ("device_{0}.txt" -f $serial)
    "serial=$serial state=$state" | Set-Content -LiteralPath $deviceLog -Encoding utf8
    if ($state -ne 'device') {
      Add-Content -LiteralPath $deviceLog -Value 'device_not_connected'
      continue
    }
    & $adb -s $serial shell getprop ro.product.model | ForEach-Object { "model=$_" } |
      Add-Content -LiteralPath $deviceLog
    & $adb -s $serial shell getprop ro.product.cpu.abi | ForEach-Object { "abi=$_" } |
      Add-Content -LiteralPath $deviceLog
    & $adb -s $serial shell dumpsys package com.fluxidi.tracking |
      Select-String -Pattern 'versionName=|versionCode=|signatures=|pkg=Package\[com.fluxidi.tracking|lastUpdateTime=|firstInstallTime=|signing ' |
      ForEach-Object { $_.Line.Trim() } |
      Add-Content -LiteralPath $deviceLog
  }
} else {
  Write-Host "ADB missing: $adb"
}

$builtAt = (Get-Date).ToString('yyyy-MM-ddTHH:mm:ssK')
$revision = 'unknown'
$dirty = 'false'
Push-Location $repo
try {
  $revText = (git rev-parse --short=12 HEAD 2>$null)
  if ($LASTEXITCODE -eq 0 -and $revText) { $revision = $revText.Trim() }
  $sourceStatus = git status --porcelain -- lib 2>$null
  if ($sourceStatus) { $dirty = 'true' }
} finally {
  Pop-Location
}

$flutter = 'C:\dev\flutter\bin\flutter.bat'
if (-not (Test-Path $flutter)) { $flutter = 'flutter' }

$defines = @(
  '--dart-define=FLUXIDI_RUNTIME_ENV=production',
  '--dart-define=FLUXIDI_LIMOUSINE_MARKETPLACE_ENTRY=true',
  "--dart-define=FLUXIDI_BUILD_TIME=$builtAt",
  "--dart-define=FLUXIDI_SOURCE_REVISION=$revision",
  "--dart-define=FLUXIDI_SOURCE_DIRTY=$dirty",
  "--dart-define=MAPBOX_TOKEN=$($env:MAPBOX_TOKEN)"
)

Write-Host 'Building release APK (production booking host, no localhost, no demo token)...'
& $flutter build apk --release --build-name=1.0.1 --build-number=10 @defines
if ($LASTEXITCODE -ne 0) { throw "flutter build apk failed: $LASTEXITCODE" }

$apk = Join-Path $repo 'build\app\outputs\flutter-apk\app-release.apk'
if (-not (Test-Path -LiteralPath $apk)) { throw "APK missing: $apk" }

$stampName = "Fluxidi-real-account-$($builtAt.Substring(0,10)).apk"
$copied = Join-Path $outDir $stampName
Copy-Item -LiteralPath $apk -Destination $copied -Force

@(
  "apk=$copied"
  "flutter_apk=$apk"
  "application_id=com.fluxidi.tracking"
  "version=1.0.1+10"
  "built_at=$builtAt"
  "source_revision=$revision"
  "source_dirty=$dirty"
  "runtime_env=production"
  "booking_host=https://fluxidi-booking-api.fluxidi.workers.dev"
  "install=not_performed"
) | Set-Content -LiteralPath (Join-Path $outDir 'apk_build_stamp.txt') -Encoding utf8

Write-Host "APK ready: $copied"
Write-Host 'Not installed. Same package as Play Fluxidi; install would update in place if signatures match.'

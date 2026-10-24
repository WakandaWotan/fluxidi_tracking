param(
  [Parameter(Mandatory=$true)][string]$ProductionDefinesPath,
  [Parameter(Mandatory=$true)][string]$SigningPropertiesPath,
  [string]$Flutter='flutter'
)
$ErrorActionPreference='Stop'
$release=Get-Content (Join-Path $PSScriptRoot 'RELEASE.json') -Raw | ConvertFrom-Json
if((Get-FileHash -Algorithm SHA256 -LiteralPath $ProductionDefinesPath).Hash.ToLower() -ne $release.productionDefinesSha256){throw 'Production build-defines mismatch'}
$defines=(Resolve-Path -LiteralPath $ProductionDefinesPath).Path
$env:FLUXIDI_SIGNING_PROPERTIES_PATH=(Resolve-Path -LiteralPath $SigningPropertiesPath).Path
$source=Join-Path $PSScriptRoot 'source'
$registrant=Join-Path $source 'android/app/src/main/java/io/flutter/plugins/GeneratedPluginRegistrant.java'
$releaseRegistrant=[System.IO.File]::ReadAllBytes($registrant)
Push-Location -LiteralPath $source
try {
  & $Flutter pub get --offline
  if($LASTEXITCODE -ne 0){throw 'Locked dependency resolution failed'}
  [System.IO.File]::WriteAllBytes($registrant,$releaseRegistrant)
  & $Flutter build appbundle --release --no-pub --build-name=1.0.7 --build-number=114 "--dart-define-from-file=$defines"
  if($LASTEXITCODE -ne 0){throw 'Release build failed'}
} finally {Pop-Location}
# Independently validate package, manifest, upload certificate and native plugin
# registration before any upload; verify_alarm_asset.py gates the known R8 fault.

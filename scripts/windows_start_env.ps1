# Shared Windows debug start: production Fluxidi vs Fluxidi — lokale test.
# Copies the Flutter Debug bundle to a stable launch folder so the other
# environment is not overwritten. Does not deploy, pay, or send messages.
param(
  [Parameter(Mandatory = $true)]
  [ValidateSet('production', 'local_test')]
  [string]$RuntimeEnv,
  [switch]$SkipBuild,
  [switch]$NoLaunch
)

$ErrorActionPreference = 'Stop'
Write-Host ("{0} windows_start_env RuntimeEnv={1}" -f (Get-Date -Format o), $RuntimeEnv)
if ([string]::IsNullOrWhiteSpace(${env:ProgramFiles(x86)})) {
  ${env:ProgramFiles(x86)} = 'C:\Program Files (x86)'
  Write-Host 'Set ProgramFiles(x86) for Flutter Windows toolchain'
}
$flutter = 'C:\dev\flutter\bin\flutter.bat'
if (-not (Test-Path $flutter)) { $flutter = 'flutter' }
$repo = Split-Path $PSScriptRoot -Parent
Set-Location $repo

$isLocal = $RuntimeEnv -eq 'local_test'
$startName = if ($isLocal) { 'Fluxidi_lokale_test' } else { 'Fluxidi' }
$shortcutName = if ($isLocal) { "Fluxidi $([char]0x2014) lokale test" } else { 'Fluxidi' }
$dest = Join-Path $repo "build\windows\starts\$startName"
$debug = Join-Path $repo 'build\windows\x64\runner\Debug'
$exeName = 'fluxidi_tracking.exe'
$destExe = Join-Path $dest $exeName
$debugExe = Join-Path $debug $exeName

$devEnv = Join-Path $env:USERPROFILE '.fluxidi\fluxidi-dev-env.ps1'
Write-Host ("{0} loading env file" -f (Get-Date -Format o))
if (Test-Path -LiteralPath $devEnv) {
  . $devEnv
  Write-Host ("{0} Fluxidi env file loaded (secret values hidden)" -f (Get-Date -Format o))
} else {
  Write-Host ("{0} Fluxidi env file missing: {1}" -f (Get-Date -Format o), $devEnv)
}

$builtAt = (Get-Date).ToString('yyyy-MM-ddTHH:mm:ssK')
$revision = 'unknown'
$dirty = 'false'
$prevEap = $ErrorActionPreference
$ErrorActionPreference = 'Continue'
try {
  Push-Location $repo
  $revText = (git rev-parse --short=12 HEAD 2>$null)
  if ($LASTEXITCODE -eq 0 -and $revText) { $revision = $revText.Trim() }
  $sourceStatus = git status --porcelain -- lib scripts 2>$null
  if ($sourceStatus) { $dirty = 'true' }
} finally {
  Pop-Location
  $ErrorActionPreference = $prevEap
}

$defines = @(
  "--dart-define=FLUXIDI_RUNTIME_ENV=$RuntimeEnv",
  '--dart-define=FLUXIDI_LIMOUSINE_MARKETPLACE_ENTRY=true',
  "--dart-define=FLUXIDI_BUILD_TIME=$builtAt",
  "--dart-define=FLUXIDI_SOURCE_REVISION=$revision",
  "--dart-define=FLUXIDI_SOURCE_DIRTY=$dirty"
)
$mapboxPresent = -not [string]::IsNullOrWhiteSpace(
  [Environment]::GetEnvironmentVariable('MAPBOX_TOKEN', 'Process')
)
if ($mapboxPresent) {
  $defines += "--dart-define=MAPBOX_TOKEN=$($env:MAPBOX_TOKEN)"
  Write-Host 'MAPBOX_TOKEN present (waarde verborgen)'
} else {
  Write-Host 'MAPBOX_TOKEN missing after env load'
}
if ($isLocal -and -not $mapboxPresent) {
  throw "MAPBOX_TOKEN ontbreekt. Verwachte bron: $devEnv"
}
if ($isLocal) {
  $defines += '--dart-define=BOOKING_BASE_URL=http://127.0.0.1:8788'
  $defines += '--dart-define=COMPANY_SESSION_TOKEN=cst_local_demo_synthetic'
  $defines += '--dart-define=FLUXIDI_DEV_COMPANY_ID=demo_company_p0'
  $defines += '--dart-define=FLUXIDI_LOCAL_QA_CUSTOMER_SESSION=true'
  $defines += '--dart-define=FLUXIDI_LOCAL_QA_ADMIN_TOKEN=local-demo-admin'
}

if (-not $isLocal) {
  if ($env:BOOKING_BASE_URL) {
    Write-Host 'Production start ignores leftover BOOKING_BASE_URL in the shell.'
  }
  if ($env:COMPANY_SESSION_TOKEN) {
    Write-Host 'Production start ignores leftover COMPANY_SESSION_TOKEN in the shell.'
  }
}

function Invoke-BoundedCmd {
  param(
    [Parameter(Mandatory = $true)][string]$FileName,
    [Parameter(Mandatory = $true)][string]$Arguments,
    [int]$TimeoutSec = 4
  )
  Write-Host ("{0} bounded {1} {2} (timeout {3}s)" -f (Get-Date -Format o), $FileName, $Arguments, $TimeoutSec)
  $out = Join-Path $env:TEMP ("fluxidi_bounded_{0}.txt" -f [Guid]::NewGuid().ToString('N'))
  $err = "$out.err"
  $p = Start-Process -FilePath $FileName -ArgumentList $Arguments -NoNewWindow -PassThru -Wait:$false `
    -RedirectStandardOutput $out -RedirectStandardError $err
  if (-not $p.WaitForExit($TimeoutSec * 1000)) {
    Write-Host ("{0} ERROR: {1} exceeded {2}s; killing child pid={3}" -f (Get-Date -Format o), $FileName, $TimeoutSec, $p.Id)
    try { $p.Kill() } catch { Write-Host ("{0} ERROR killing child: {1}" -f (Get-Date -Format o), $_) }
    return 124
  }
  $code = $p.ExitCode
  if (Test-Path -LiteralPath $out) {
    Get-Content -LiteralPath $out -ErrorAction SilentlyContinue | ForEach-Object { Write-Host $_ }
  }
  if (Test-Path -LiteralPath $err) {
    Get-Content -LiteralPath $err -ErrorAction SilentlyContinue | ForEach-Object { Write-Host ("ERR: {0}" -f $_) }
  }
  Write-Host ("{0} {1} exit={2}" -f (Get-Date -Format o), $FileName, $code)
  return $code
}

function Stop-LokaleTestWindowOnly {
  Write-Host ("{0} stopping only windows titled lokale test (not production Fluxidi)" -f (Get-Date -Format o))
  $titles = @(
    '*lokale test*',
    '*lokale-test*'
  )
  foreach ($title in $titles) {
    Invoke-BoundedCmd -FileName 'taskkill.exe' -Arguments "/F /FI `"IMAGENAME eq fluxidi_tracking.exe`" /FI `"WINDOWTITLE eq $title`"" -TimeoutSec 4 | Out-Null
  }
}

if (-not $SkipBuild) {
  if ($isLocal) {
    Stop-LokaleTestWindowOnly
  } else {
    Write-Host ("{0} production start does not title-kill local windows" -f (Get-Date -Format o))
  }
  Start-Sleep -Milliseconds 400
  Write-Host ("{0} Building Windows debug for {1}" -f (Get-Date -Format o), $shortcutName)
  $prevFlutterEap = $ErrorActionPreference
  $ErrorActionPreference = 'Continue'
  & $flutter build windows --debug @defines
  $flutterCode = $LASTEXITCODE
  $ErrorActionPreference = $prevFlutterEap
  if ($flutterCode -ne 0) {
    throw "flutter build windows failed with $flutterCode"
  }
}

if (-not (Test-Path $debugExe)) {
  throw "Missing $debugExe. Run without -SkipBuild first."
}

New-Item -ItemType Directory -Force -Path $dest | Out-Null
& robocopy $debug $dest /E /NFL /NDL /NJH /NJS /NC /NS /NP | Out-Null
if ($LASTEXITCODE -ge 8) {
  throw "robocopy failed with $LASTEXITCODE"
}

function New-FluxidiShortcut(
  [string]$Name,
  [string]$Target,
  [string]$WorkDir,
  [string]$Arguments = '',
  [string]$IconPath = ''
) {
  $shell = New-Object -ComObject WScript.Shell
  $places = @(
    (Join-Path $repo 'starts'),
    [Environment]::GetFolderPath('Desktop')
  )
  $names = @($Name)
  if ($isLocal) {
    $existingLocal = @()
    foreach ($place in $places) {
      if (-not $place -or -not (Test-Path -LiteralPath $place)) { continue }
      $existingLocal += Get-ChildItem -LiteralPath $place -Filter '*.lnk' |
        Where-Object { $_.BaseName -match 'lokale test' } |
        ForEach-Object { $_.BaseName }
    }
    if ($existingLocal.Count -gt 0) {
      $names = @($existingLocal | Select-Object -Unique)
    }
  }
  foreach ($place in $places) {
    if (-not $place) { continue }
    New-Item -ItemType Directory -Force -Path $place | Out-Null
    foreach ($itemName in ($names | Select-Object -Unique)) {
      $lnk = Join-Path $place ($itemName + '.lnk')
      $sc = $shell.CreateShortcut($lnk)
      $sc.TargetPath = $Target
      $sc.Arguments = $Arguments
      $sc.WorkingDirectory = $WorkDir
      $sc.WindowStyle = 1
      $sc.Description = $Name
      if ($IconPath) { $sc.IconLocation = "$IconPath,0" }
      $sc.Save()
      Write-Host "Shortcut: $lnk"
    }
  }
}

Set-Content -Path (Join-Path $dest 'fluxidi_window_title.txt') -Value $shortcutName -Encoding utf8
$stampPath = Join-Path $dest 'fluxidi_build_stamp.txt'
@(
  "environment=$shortcutName"
  "runtime_env=$RuntimeEnv"
  "built_at=$builtAt"
  "source_revision=$revision"
  "source_dirty=$dirty"
  "exe=$destExe"
) | Set-Content -Path $stampPath -Encoding utf8

$launchScript = Join-Path $PSScriptRoot 'launch_fluxidi_lokale_test_windows.ps1'
$shortcutTarget = $destExe
$shortcutArgs = ''
$shortcutWorkDir = $dest
if ($isLocal) {
  $shortcutTarget = Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
  $shortcutArgs = "-NoProfile -ExecutionPolicy Bypass -File `"$launchScript`""
}

New-FluxidiShortcut -Name $shortcutName -Target $shortcutTarget -WorkDir $shortcutWorkDir `
  -Arguments $shortcutArgs -IconPath $destExe

Write-Host "Startpunt: $shortcutName"
Write-Host "Exe: $destExe"
Write-Host "Built: $builtAt"
Write-Host "Source: $revision dirty=$dirty"
if ($isLocal) {
  Write-Host 'Booking host: http://127.0.0.1:8788'
} else {
  Write-Host 'Booking host: https://fluxidi-booking-api.fluxidi.workers.dev'
}
Write-Host 'Tracking host: https://fluxidi-tracking-api.fluxidi.workers.dev'
Write-Host 'Navigation host: https://fluxidi-navigation-api.fluxidi.workers.dev'
Write-Host 'No host fallback. Enter a personal company code in the app; this script does not log codes or tokens.'

if (-not $NoLaunch) {
  if ($isLocal) {
    & $launchScript
  } else {
    Start-Process -FilePath $destExe -WorkingDirectory $dest
    Write-Host "Launched $shortcutName"
  }
}

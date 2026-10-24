# Flutter Windows desktop — full app shell against the local Worker.
# Named start point: Fluxidi — lokale test.
# Rebuilds the desktop start copy. The shortcut then checks/starts the Worker.
# Real company pairing: scripts/start_fluxidi_windows.ps1
$ErrorActionPreference = 'Stop'
& (Join-Path $PSScriptRoot 'windows_start_env.ps1') -RuntimeEnv local_test

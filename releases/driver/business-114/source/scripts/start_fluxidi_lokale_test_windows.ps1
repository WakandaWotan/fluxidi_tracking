# Rebuild the Fluxidi — lokale test start copy Christophe opens from the desktop.
# Source edits or hot reload in another window are not this copy.
# The desktop shortcut launches launch_fluxidi_lokale_test_windows.ps1, which
# checks/starts the local Worker and keeps .local-customer-ops-demo persist.
$ErrorActionPreference = 'Stop'
Write-Host ("{0} start_fluxidi_lokale_test_windows begin" -f (Get-Date -Format o))
& (Join-Path $PSScriptRoot 'windows_start_env.ps1') -RuntimeEnv local_test
Write-Host ("{0} start_fluxidi_lokale_test_windows end" -f (Get-Date -Format o))

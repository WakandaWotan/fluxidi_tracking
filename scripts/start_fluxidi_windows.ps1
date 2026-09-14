# Christophe's normal Windows start: Fluxidi against the production booking host.
# Does not pass BOOKING_BASE_URL or a demo company token.
$ErrorActionPreference = 'Stop'
& (Join-Path $PSScriptRoot 'windows_start_env.ps1') -RuntimeEnv production

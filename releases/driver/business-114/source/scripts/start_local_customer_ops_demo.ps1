# Flutter Klantenbeheer local demo against http://127.0.0.1:8788
# Start the Worker first: workers/booking/start_local_customer_ops_demo.ps1
$ErrorActionPreference = 'Stop'
$flutter = 'C:\dev\flutter\bin\flutter.bat'
if (-not (Test-Path $flutter)) { $flutter = 'flutter' }
Set-Location (Split-Path $PSScriptRoot -Parent)
& $flutter run -d chrome `
  --target=lib/company/company_customer_ops_local_demo.dart `
  --web-hostname 127.0.0.1 `
  --web-port 8099 `
  --dart-define=BOOKING_BASE_URL=http://127.0.0.1:8788 `
  --dart-define=COMPANY_SESSION_TOKEN=cst_local_demo_synthetic `
  --dart-define=FLUXIDI_DEV_COMPANY_ID=demo_company_p0

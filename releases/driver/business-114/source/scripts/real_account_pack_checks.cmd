@echo off
setlocal
set OUT=C:\_flutter_work\fluxidi_customer_ops_client_p0\.qa-local\real-account
set WORKER=C:\_flutter_work\fluxidi_customer_ops_worker_p0\workers\booking
set REPO=C:\_flutter_work\fluxidi_customer_ops_client_p0
set ADB=%LOCALAPPDATA%\Android\Sdk\platform-tools\adb.exe
mkdir "%OUT%" 2>nul

echo === node check ===
cd /d "%WORKER%"
node --check fluxidi_booking_worker.js
if errorlevel 1 exit /b 1

echo === wrangler deployments ===
wrangler deployments list --config wrangler.real-account-release.toml > "%OUT%\worker_deployments_live.txt" 2>&1
type "%OUT%\worker_deployments_live.txt"

echo === adb devices ===
"%ADB%" start-server
"%ADB%" devices -l > "%OUT%\adb_devices.txt"
type "%OUT%\adb_devices.txt"

echo === pull installed APKs ===
for %%S in (SG7XLZ7TKRLZOJTG R52Y808CN2M) do (
  "%ADB%" -s %%S shell pm path com.fluxidi.tracking > "%OUT%\pm_path_%%S.txt"
  for /f "tokens=2 delims=:" %%P in ('findstr /i "base.apk" "%OUT%\pm_path_%%S.txt"') do (
    "%ADB%" -s %%S pull "%%P" "%OUT%\installed_%%S.apk"
  )
)

echo === done pull ===
exit /b 0

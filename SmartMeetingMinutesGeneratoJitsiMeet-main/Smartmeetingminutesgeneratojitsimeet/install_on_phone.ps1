# Build and install the app on the connected Android device (primary user).
# Use this if "flutter install" leaves the app on a different profile (e.g. work profile).
# Requires: USB debugging on, device connected.

$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot

Write-Host "Building release APK..." -ForegroundColor Cyan
flutter build apk --release
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

$apk = "build\app\outputs\flutter-apk\app-release.apk"
if (-not (Test-Path $apk)) {
    Write-Host "APK not found: $apk" -ForegroundColor Red
    exit 1
}

Write-Host "Installing on device (primary user)..." -ForegroundColor Cyan
& "${env:LOCALAPPDATA}\Android\sdk\platform-tools\adb.exe" install -t -r --user 0 (Resolve-Path $apk).Path
if ($LASTEXITCODE -ne 0) {
    Write-Host "Install failed. Try: flutter install --release -d <device_id>" -ForegroundColor Yellow
    exit $LASTEXITCODE
}

Write-Host "Done. Open the app on your phone (Smart Meeting Minutes)." -ForegroundColor Green

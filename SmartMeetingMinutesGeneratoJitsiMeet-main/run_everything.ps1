<#
One-click launcher: starts Flask backend (port 5000).
Usage: .\run_everything.ps1
#>

$ErrorActionPreference = "Stop"

$projectRoot = $PSScriptRoot
$flutterDir = Join-Path $projectRoot "Smartmeetingminutesgeneratojitsimeet"
$serversScript = Join-Path $projectRoot "run_both_servers.ps1"

if (-not (Test-Path $serversScript)) {
    throw "Missing script: $serversScript"
}

if (-not (Test-Path $flutterDir)) {
    throw "Flutter app folder not found: $flutterDir"
}

Write-Host "" 
Write-Host "============================================" -ForegroundColor Cyan
Write-Host "  Smart Meeting Minutes - Start Services" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Write-Host ""

# 1) Start/verify bot + backend
& $serversScript

Write-Host ""
Write-Host "Release mode workflow: install APK manually on phone and keep server windows open." -ForegroundColor Green
Write-Host "APK: Smartmeetingminutesgeneratojitsimeet\build\app\outputs\flutter-apk\app-release.apk" -ForegroundColor Gray
Write-Host ""
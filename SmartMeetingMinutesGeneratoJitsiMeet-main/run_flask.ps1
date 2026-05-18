<#
  Start Flask backend only (Smart Meeting Minutes).
  Flask runs the Jitsi bot, recording, and minutes generation on port 5000.

  Usage: .\run_flask.ps1
#>

$ErrorActionPreference = "Stop"
$projectRoot = $PSScriptRoot
$backendDir = Join-Path $projectRoot "minutes_generator_jitsi_meet"

if (-not (Test-Path $backendDir)) {
    throw "Flask backend folder not found: $backendDir"
}

# Optional: show LAN IP for phone
$ip = $null
try {
    $addrs = Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue | Where-Object {
        $_.IPAddress -match '^\d+\.\d+\.\d+\.\d+$' -and
        $_.IPAddress -notmatch '^127\.' -and
        $_.IPAddress -notmatch '^169\.'
    }
    if ($addrs) { $ip = ($addrs | Select-Object -First 1).IPAddress }
} catch {}
if ([string]::IsNullOrWhiteSpace($ip)) { $ip = "localhost" }

Write-Host ""
Write-Host "============================================" -ForegroundColor Cyan
Write-Host "  Smart Meeting Minutes - Flask Backend" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "In app set Flask Server URL: http://${ip}:5000" -ForegroundColor White
Write-Host ""

Set-Location $backendDir
python app.py

# Start the Jitsi bot server and show the URL to use in the app.
# Run this on your PC. Then on your phone enter the URL shown below in the app.

$port = 3000

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Jitsi Bot Server" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# Show IPv4 addresses (skip loopback)
$addrs = Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.InterfaceAlias -notmatch 'Loopback' -and $_.IPAddress -notmatch '^169\.' }
if ($addrs) {
    Write-Host "Use this URL in the app (phone must be on same Wi-Fi):" -ForegroundColor Yellow
    foreach ($a in $addrs) {
        $url = "http://$($a.IPAddress):$port"
        Write-Host "  $url" -ForegroundColor Green
    }
    Write-Host ""
} else {
    Write-Host "Could not detect IP. Use: http://YOUR_PC_IP:$port" -ForegroundColor Yellow
    Write-Host "Find IP: run 'ipconfig' and look for IPv4 Address" -ForegroundColor Gray
    Write-Host ""
}

# Try to add firewall rule (works only if this script is run as Administrator)
$ruleName = "Jitsi Bot Server Port $port"
$existing = Get-NetFirewallRule -DisplayName $ruleName -ErrorAction SilentlyContinue
if (-not $existing) {
    try {
        New-NetFirewallRule -DisplayName $ruleName -Direction Inbound -LocalPort $port -Protocol TCP -Action Allow | Out-Null
        Write-Host "Firewall: rule added for port $port." -ForegroundColor Green
    } catch {
        Write-Host "If phone cannot connect: Right-click ADD_FIREWALL_RULE.ps1 -> Run with PowerShell (as Admin)" -ForegroundColor Yellow
    }
    Write-Host ""
}

Write-Host "Starting server... (keep this window open)" -ForegroundColor Cyan
Write-Host ""

Set-Location $PSScriptRoot
if (-not (Test-Path "node_modules")) {
    Write-Host "Installing dependencies (npm install)..." -ForegroundColor Gray
    npm install
}
Write-Host "Bot mode: visible browser (BOT_HEADLESS=false)" -ForegroundColor Gray
$env:BOT_HEADLESS = "false"
node server.js

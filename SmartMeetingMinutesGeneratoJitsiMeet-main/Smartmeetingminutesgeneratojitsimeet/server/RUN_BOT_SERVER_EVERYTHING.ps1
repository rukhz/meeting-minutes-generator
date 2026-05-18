# ALL-IN-ONE: Show your IP, add firewall rule, npm install, start bot server.
# Run this on the PC. Then on your phone: same Wi-Fi, enter the URL below in the app.

$ErrorActionPreference = "Stop"
$port = 3000
$ruleName = "Jitsi Bot Server Port $port"

Write-Host ""
Write-Host "============================================" -ForegroundColor Cyan
Write-Host "  Smart Meeting Minutes - Bot Server" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Write-Host ""

# 1. Get and show IP
$addrs = Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue | Where-Object {
    $_.InterfaceAlias -notmatch 'Loopback' -and $_.IPAddress -notmatch '^169\.'
}
$myIp = $null
if ($addrs) {
    $myIp = ($addrs | Select-Object -First 1).IPAddress
    Write-Host "Your PC IP address: " -NoNewline
    Write-Host $myIp -ForegroundColor Green
    $url = "http://${myIp}:${port}"
    Write-Host ""
    Write-Host ">>> PUT THIS IN THE APP (Server URL): " -ForegroundColor Yellow
    Write-Host "    $url" -ForegroundColor White
    Write-Host ""
} else {
    Write-Host "Could not detect IP. Run 'ipconfig' and use your IPv4 Address." -ForegroundColor Yellow
    Write-Host "Server URL format: http://YOUR_IP:$port" -ForegroundColor Gray
    Write-Host ""
}

# 2. Add firewall rule (need Admin for this)
$existing = Get-NetFirewallRule -DisplayName $ruleName -ErrorAction SilentlyContinue
if (-not $existing) {
    try {
        New-NetFirewallRule -DisplayName $ruleName -Direction Inbound -LocalPort $port -Protocol TCP -Action Allow | Out-Null
        Write-Host "Firewall: port $port allowed for incoming connections." -ForegroundColor Green
    } catch {
        Write-Host "Firewall: could not add rule (run PowerShell as Administrator and run ADD_FIREWALL_RULE.ps1)." -ForegroundColor Yellow
    }
} else {
    Write-Host "Firewall: port $port already allowed." -ForegroundColor Green
}
Write-Host ""

# 3. npm install if needed
Set-Location $PSScriptRoot
if (-not (Test-Path "node_modules")) {
    Write-Host "Installing npm packages (first time)..." -ForegroundColor Cyan
    npm install
    if ($LASTEXITCODE -ne 0) { Write-Host "npm install failed." -ForegroundColor Red; exit 1 }
    Write-Host ""
}

# 4. Start server
Write-Host "Starting bot server on port $port... (keep this window open)" -ForegroundColor Cyan
Write-Host "Phone must be on the SAME Wi-Fi as this PC." -ForegroundColor Gray
Write-Host "Bot mode: visible browser (BOT_HEADLESS=false)" -ForegroundColor Gray
Write-Host ""
$env:BOT_HEADLESS = "false"
node server.js

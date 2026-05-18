# Run this script AS ADMINISTRATOR once to allow the phone to reach the bot server.
# Right-click PowerShell -> Run as Administrator, then: cd path\to\server; .\ADD_FIREWALL_RULE.ps1

$port = 3000
$ruleName = "Jitsi Bot Server Port $port"

$existing = Get-NetFirewallRule -DisplayName $ruleName -ErrorAction SilentlyContinue
if ($existing) {
    Write-Host "Firewall rule '$ruleName' already exists." -ForegroundColor Green
    exit 0
}

try {
    New-NetFirewallRule -DisplayName $ruleName -Direction Inbound -LocalPort $port -Protocol TCP -Action Allow
    Write-Host "Added firewall rule. Port $port is now allowed. Try connecting from the phone again." -ForegroundColor Green
} catch {
    Write-Host "Failed. Make sure you run this script as Administrator." -ForegroundColor Red
    Write-Host $_.Exception.Message
    exit 1
}

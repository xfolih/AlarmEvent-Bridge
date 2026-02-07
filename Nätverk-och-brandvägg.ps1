# Hjalp for att fa webhook-mottagaren att ta emot fran andra datorn.
# Kora pa den dator som ska MOTTA webhooks (där Start-WebhookReceiver.ps1 kors).
# Krav: PowerShell kors som administratör (hogerklick -> Kör som administratör).

$ErrorActionPreference = "Stop"

Write-Host "=== 1. Kontrollerar IP-adresser pa denna dator ===" -ForegroundColor Cyan
Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.IPAddress -ne "127.0.0.1" } | Format-Table InterfaceAlias, IPAddress, PrefixLength -AutoSize
Write-Host "Notera vilken IP som tillhor din Ethernet/Wi-Fi (t.ex. 192.168.0.38)." -ForegroundColor Gray
Write-Host ""

Write-Host "=== 2. Tillater inkommande trafik pa port 8765 (webhook) ===" -ForegroundColor Cyan
$ruleName = "Milestone Webhook Receiver 8765"
$existing = Get-NetFirewallRule -DisplayName $ruleName -ErrorAction SilentlyContinue
if ($existing) {
    Write-Host "Regeln finns redan. Ingen andring." -ForegroundColor Green
} else {
    New-NetFirewallRule -DisplayName $ruleName -Direction Inbound -Protocol TCP -LocalPort 8765 -Action Allow
    Write-Host "Regel tillagd: inkommande TCP 8765 tillaten." -ForegroundColor Green
}
Write-Host ""

Write-Host "=== 3. (Valfritt) Tillat ping for att kunna pinga denna dator ===" -ForegroundColor Cyan
$pingRule = Get-NetFirewallRule -DisplayName "File and Printer Sharing (Echo Request - ICMPv4-In)" -ErrorAction SilentlyContinue
if ($pingRule) {
    Set-NetFirewallRule -DisplayName "File and Printer Sharing (Echo Request - ICMPv4-In)" -Enabled True
    Write-Host "Ping (ICMP) aktiverat." -ForegroundColor Green
} else {
    Write-Host "Aktivera ping manuellt i Windows Defender-brandvagg: Inbound rules -> Core Networking -> ping." -ForegroundColor Gray
}
Write-Host ""
Write-Host "Klart. Starta da: .\Start-WebhookReceiver.ps1 -BindAddress DIN_IP" -ForegroundColor Yellow
Write-Host "Test fran andra datorn: Invoke-WebRequest -Uri http://DIN_IP:8765/test -Method POST -Body '{}' -ContentType application/json" -ForegroundColor Gray

# Oppna port 8765 for webhook-mottagaren sa att andra datorer kan nara.
# Kora pa datorn som MOTTAR (där Start-WebhookReceiver kors). Krav: Kör som administratör.

$ErrorActionPreference = "Stop"
$ruleName = "Milestone Webhook Receiver 8765"
$existing = Get-NetFirewallRule -DisplayName $ruleName -ErrorAction SilentlyContinue
if ($existing) {
    Write-Host "Port 8765 ar redan tillaten." -ForegroundColor Green
} else {
    New-NetFirewallRule -DisplayName $ruleName -Direction Inbound -Protocol TCP -LocalPort 8765 -Action Allow
    Write-Host "Port 8765 oppnad for inkommande trafik." -ForegroundColor Green
}
Write-Host "Starta mottagaren med: .\Start-WebhookReceiver.ps1 -BindAddress 192.168.0.38" -ForegroundColor Yellow

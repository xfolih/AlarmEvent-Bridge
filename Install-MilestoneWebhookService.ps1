# Installer script for AlarmEvent Bridge as Windows Service
# Run as Administrator: .\Install-MilestoneWebhookService.ps1

param(
    [string]$ServiceName = "AlarmEventBridge",
    [string]$DisplayName = "AlarmEvent Bridge",
    [string]$Description = "Monitors Milestone XProtect events and sends webhooks to alarm center"
)

$ErrorActionPreference = "Stop"

# Check if running as Administrator
$currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "ERROR: This script must be run as Administrator!" -ForegroundColor Red
    Write-Host "Right-click PowerShell and select 'Run as Administrator'" -ForegroundColor Yellow
    exit 1
}

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$exePath = Join-Path $scriptDir "AlarmEventBridge.exe"
$watchdogPath = Join-Path $scriptDir "Run-MilestoneWebhookBridgeWatchdog.ps1"

if (-not (Test-Path $exePath)) {
    Write-Host "ERROR: AlarmEventBridge.exe not found at: $exePath" -ForegroundColor Red
    Write-Host "Please build the project first (Release configuration)" -ForegroundColor Yellow
    exit 1
}

# Check if service already exists
$existingService = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
if ($existingService) {
    Write-Host "Service '$ServiceName' already exists. Stopping and removing..." -ForegroundColor Yellow
    Stop-Service -Name $ServiceName -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2
    sc.exe delete $ServiceName | Out-Null
    Start-Sleep -Seconds 2
}

# Create service using sc.exe (more reliable than New-Service)
Write-Host "Creating Windows Service '$ServiceName'..." -ForegroundColor Cyan
$binPath = "powershell.exe -NoProfile -ExecutionPolicy Bypass -File `"$watchdogPath`""
$result = sc.exe create $ServiceName binPath= "$binPath" start= auto DisplayName= "$DisplayName"
if ($LASTEXITCODE -ne 0) {
    Write-Host "ERROR: Failed to create service. Error: $result" -ForegroundColor Red
    exit 1
}

# Set service description
sc.exe description $ServiceName "$Description"

# Configure service recovery (restart on failure)
Write-Host "Configuring service recovery (auto-restart on failure)..." -ForegroundColor Cyan
sc.exe failure $ServiceName reset= 86400 actions= restart/60000/restart/60000/restart/60000

# Start service
Write-Host "Starting service..." -ForegroundColor Cyan
Start-Service -Name $ServiceName
Start-Sleep -Seconds 2

$service = Get-Service -Name $ServiceName
if ($service.Status -eq "Running") {
    Write-Host "SUCCESS: Service '$ServiceName' is now running!" -ForegroundColor Green
    Write-Host ""
    Write-Host "Service Information:" -ForegroundColor Cyan
    Write-Host "  Name: $($service.Name)"
    Write-Host "  Display Name: $($service.DisplayName)"
    Write-Host "  Status: $($service.Status)"
    Write-Host "  Startup Type: $($service.StartType)"
    Write-Host ""
    Write-Host "To manage the service:" -ForegroundColor Yellow
    Write-Host "  Stop:   Stop-Service -Name $ServiceName"
    Write-Host "  Start:  Start-Service -Name $ServiceName"
    Write-Host "  Status: Get-Service -Name $ServiceName"
    Write-Host "  Logs:   Get-EventLog -LogName Application -Source $ServiceName -Newest 50"
} else {
    Write-Host "WARNING: Service created but not running. Status: $($service.Status)" -ForegroundColor Yellow
    Write-Host "Check Event Viewer for errors." -ForegroundColor Yellow
}

# Watchdog script - runs the bridge and restarts it if it crashes
# This script is designed to run as a Windows Service

$ErrorActionPreference = "Continue"
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$logDir = Join-Path $scriptDir "Logs"
$logFile = Join-Path $logDir "BridgeWatchdog.log"
$bridgeScript = Join-Path $scriptDir "Start-MilestoneWebhookBridge.ps1"

# Create log directory if it doesn't exist
if (-not (Test-Path $logDir)) {
    New-Item -ItemType Directory -Path $logDir -Force | Out-Null
}

function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "[$timestamp] [$Level] $Message"
    Add-Content -Path $logFile -Value $logMessage -Encoding UTF8
    # Also write to console if running interactively
    if ($Host.Name -eq "ConsoleHost") {
        Write-Host $logMessage
    }
}

function Start-Bridge {
    Write-Log "Starting Milestone Webhook Bridge..."
    $process = Start-Process -FilePath "powershell.exe" `
        -ArgumentList "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", "`"$bridgeScript`"" `
        -WorkingDirectory $scriptDir `
        -PassThru `
        -NoNewWindow `
        -RedirectStandardOutput (Join-Path $logDir "BridgeOutput.log") `
        -RedirectStandardError (Join-Path $logDir "BridgeError.log")
    
    return $process
}

# Main watchdog loop
Write-Log "Watchdog started. Monitoring bridge process..."
$restartCount = 0
$maxRestartsPerHour = 10
$restartWindow = New-TimeSpan -Hours 1
$restartTimes = @()

while ($true) {
    try {
        $process = Start-Bridge
        $processId = $process.Id
        Write-Log "Bridge process started (PID: $processId)"
        
        # Monitor process
        while (-not $process.HasExited) {
            Start-Sleep -Seconds 10
            
            # Check if process is still responsive (optional - can be removed if too aggressive)
            try {
                $null = Get-Process -Id $processId -ErrorAction Stop
            } catch {
                Write-Log "Process $processId no longer exists. Restarting..." "WARN"
                break
            }
        }
        
        # Process exited
        $exitCode = $process.ExitCode
        Write-Log "Bridge process exited with code: $exitCode" "WARN"
        
        # Check restart rate limiting
        $now = Get-Date
        $restartTimes = $restartTimes | Where-Object { ($now - $_) -lt $restartWindow }
        
        if ($restartTimes.Count -ge $maxRestartsPerHour) {
            Write-Log "Too many restarts in the last hour ($($restartTimes.Count)). Waiting 5 minutes before retry..." "ERROR"
            Start-Sleep -Seconds 300
            $restartTimes = @()
        }
        
        $restartCount++
        $restartTimes += $now
        Write-Log "Restarting bridge (restart #$restartCount). Waiting 10 seconds..." "WARN"
        Start-Sleep -Seconds 10
        
    } catch {
        Write-Log "Watchdog error: $($_.Exception.Message)" "ERROR"
        Write-Log "Stack trace: $($_.ScriptStackTrace)" "ERROR"
        Start-Sleep -Seconds 30
    }
}

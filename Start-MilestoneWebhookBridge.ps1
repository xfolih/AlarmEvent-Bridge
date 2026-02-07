# Reads WebhookConfig.json and Credentials, keeps token fresh, listens to Events & State
# and sends webhook when analysis + IO active. Run: .\Start-MilestoneWebhookBridge.ps1

$ErrorActionPreference = "Stop"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $ScriptDir

# Setup logging
$logDir = Join-Path $ScriptDir "Logs"
if (-not (Test-Path $logDir)) {
    New-Item -ItemType Directory -Path $logDir -Force | Out-Null
}
$logFile = Join-Path $logDir "Bridge_$(Get-Date -Format 'yyyy-MM-dd').log"
$maxLogSizeMB = 50
$maxLogFiles = 7

function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "[$timestamp] [$Level] $Message"
    
    # Write to log file
    try {
        Add-Content -Path $logFile -Value $logMessage -Encoding UTF8 -ErrorAction SilentlyContinue
    } catch {
        # If log file is locked, try again
        Start-Sleep -Milliseconds 100
        Add-Content -Path $logFile -Value $logMessage -Encoding UTF8 -ErrorAction SilentlyContinue
    }
    
    # Also write to console with color
    $color = switch ($Level) {
        "ERROR" { "Red" }
        "WARN"  { "Yellow" }
        "INFO"  { "Cyan" }
        default { "White" }
    }
    Write-Host $logMessage -ForegroundColor $color
}

function Rotate-Logs {
    # Check log file size and rotate if needed
    if (Test-Path $logFile) {
        $logSize = (Get-Item $logFile).Length / 1MB
        if ($logSize -gt $maxLogSizeMB) {
            $archiveFile = $logFile -replace '\.log$', "_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
            Move-Item -Path $logFile -Destination $archiveFile -Force
            Write-Log "Log rotated: $archiveFile" "INFO"
        }
    }
    
    # Clean up old log files (keep last 7 days)
    Get-ChildItem -Path $logDir -Filter "Bridge_*.log" | 
        Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-$maxLogFiles) } | 
        Remove-Item -Force -ErrorAction SilentlyContinue
}

# Rotate logs on startup
Rotate-Logs
Write-Log "=== Bridge starting ===" "INFO"

. .\MilestoneApi.ps1

$configPath = Join-Path $ScriptDir "WebhookConfig.json"
$credPath = Join-Path $ScriptDir "Credentials.ps1"
if (-not (Test-Path $configPath)) {
    Write-Host "Run Setup-MilestoneWebhookConfig.ps1 first to create WebhookConfig.json" -ForegroundColor Red
    exit 1
}
if (-not (Test-Path $credPath)) {
    Write-Host "Missing Credentials.ps1. Run Setup-MilestoneWebhookConfig.ps1 first." -ForegroundColor Red
    exit 1
}

. $credPath
$Script:MilestoneApiBaseUrl = $MilestoneApiBaseUrl
$Script:MilestoneUsername = $MilestoneUsername
$Script:MilestonePassword = $MilestonePassword

if ($Script:MilestoneApiBaseUrl -like "https://*") {
    [System.Net.ServicePointManager]::ServerCertificateValidationCallback = { $true }
    [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12
}

$config = Get-Content $configPath -Raw | ConvertFrom-Json
$cameras = @($config.cameras | Where-Object { $_.enabled -ne $false })
# Require IO active: if false, webhook is sent on analysis event regardless of IO status
$requireIoActive = $true
if ($config.requireIoActive -eq $false) { $requireIoActive = $false }
if (-not $requireIoActive) { 
    Write-Log "WARNING: Webhook will be sent on analysis event regardless of alarm status (requireIoActive=false)." "WARN"
    Write-Host "WARNING: Webhook will be sent on analysis event regardless of alarm status (requireIoActive=false)." -ForegroundColor Yellow 
}

# Plan B: Collect user-defined events from cameras (each camera can have its own alarm active/inactive events)
$alarmActiveEventTypeIds = @($cameras | Where-Object { $_.alarmActiveEventTypeId } | ForEach-Object { $_.alarmActiveEventTypeId } | Select-Object -Unique)
$alarmInactiveEventTypeIds = @($cameras | Where-Object { $_.alarmInactiveEventTypeId } | ForEach-Object { $_.alarmInactiveEventTypeId } | Select-Object -Unique)
$useAlarmEvents = ($alarmActiveEventTypeIds.Count -gt 0 -and $alarmInactiveEventTypeIds.Count -gt 0)
$alarmActive = $false
if ($useAlarmEvents) { 
    $msg = "Plan B: Alarm status from user-defined events (active: $($alarmActiveEventTypeIds -join ', '), inactive: $($alarmInactiveEventTypeIds -join ', '))."
    Write-Log $msg "INFO"
    Write-Host $msg -ForegroundColor Cyan 
}
if ($cameras.Count -eq 0) {
    Write-Log "No cameras in configuration. Exiting." "ERROR"
    Write-Host "No cameras in configuration." -ForegroundColor Red
    exit 1
}

# IO status per ioSourceId (lowercase so matching works regardless of API format)
$ioState = @{}
foreach ($c in $cameras) {
    if ($c.ioSourceId) { $ioState[$c.ioSourceId.ToString().ToLowerInvariant()] = $false }
}

# Token refreshed 5 min before expiration
$RefreshBeforeSeconds = 300
# Reconnection: backoff (s) to avoid log flooding and server load
$reconnectDelaySec = 15
$reconnectDelayMax = 120
$connectedSince = $null

# Build payload in same format as Milestone's built-in webhook (Event + Site)
function New-MilestoneEventPayload {
    param([string]$CameraId, [string]$CameraName, [string]$MessageId, [string]$Timestamp)
    $base = $config.apiBaseUrl.TrimEnd("/")
    $uri = [Uri]$base
    $serverHostname = $uri.Host
    $scheme = $uri.Scheme
    $port = $uri.Port
    if ($port -le 0) { $port = if ($scheme -eq "https") { 443 } else { 80 } }
    $absoluteUri = if ($base) { $base + "/" } else { "$scheme`://$serverHostname`:$port/" }
    $serverId = [guid]::NewGuid().ToString()
    $eventId = [guid]::NewGuid().ToString()
    $payload = @{
        Event = @{
            EventHeader = @{
                ID           = $eventId
                Timestamp    = $Timestamp
                Type         = "System Event"
                Version      = "1.0"
                Priority     = 1
                PriorityName = "High"
                Name         = "<Unknown>"
                Message      = "<Unknown>"
                Source       = @{
                    Name  = $CameraName
                    FQID  = @{
                        ServerId  = @{
                            Type     = "XPCORS"
                            Hostname = $serverHostname
                            Port     = $port
                            Id       = $serverId
                            Scheme   = $scheme
                        }
                        ParentId   = $serverId
                        ObjectId   = $CameraId
                        FolderType = 0
                        Kind       = "5135ba21-f1dc-4321-806a-6ce2017343c0"
                    }
                }
                MessageId = $MessageId
            }
        }
        Site = @{
            ServerHostname = $serverHostname
            AbsoluteUri    = $absoluteUri
            ServerType     = "XPCO"
        }
    }
    return $payload
}

function Send-Webhook {
    param([string]$Url, [object]$Payload)
    try {
        $body = if ($Payload) { $Payload | ConvertTo-Json -Depth 10 -Compress } else { "{}" }
        $response = Invoke-RestMethod -Uri $Url -Method Post -Body $body -ContentType "application/json" -TimeoutSec 10
        # Suppress response output to keep log clean (only show if there's an error)
        return $null
    } catch {
        $errorMsg = "Webhook error $Url : $($_.Exception.Message)"
        Write-Log $errorMsg "ERROR"
        Write-Host $errorMsg -ForegroundColor Red
    }
}

# WebSocket: connect, authenticate, startSession, addSubscription, read messages
$wsBase = $config.apiBaseUrl.TrimEnd("/").Replace("https://", "wss://").Replace("http://", "ws://")
$wsUri = [Uri]($wsBase + "/api/ws/events/v1")

Write-Log "=== Webhook bridge starting ===" "INFO"
Write-Log "Cameras configured: $($cameras.Count)" "INFO"
Write-Log "Token refreshed automatically before expiration (production-ready solution)." "INFO"
Write-Log "WebSocket stays open continuously - no timeouts." "INFO"
Write-Host "=== Webhook bridge starting ===" -ForegroundColor Cyan
Write-Host "Cameras configured: $($cameras.Count)" -ForegroundColor Cyan
Write-Host "Token refreshed automatically before expiration (production-ready solution)." -ForegroundColor Cyan
Write-Host "WebSocket stays open continuously - no timeouts." -ForegroundColor Cyan
Write-Host ""

$buffer = New-Object byte[] 65536
$run = $true

while ($run) {
    try {
        $token = Get-MilestoneToken -RefreshBeforeSeconds $RefreshBeforeSeconds
        $cts = $null
        $ws = New-Object System.Net.WebSockets.ClientWebSocket
        $ws.Options.SetRequestHeader("Authorization", "Bearer $token")
        $cts = New-Object System.Threading.CancellationTokenSource
        $conn = $ws.ConnectAsync($wsUri, $cts.Token)
        $null = $conn.Wait(15000)
        if ($ws.State -ne "Open") {
            $msg = "WebSocket could not be opened. Retrying in 30 s."
            Write-Log $msg "WARN"
            Write-Host $msg -ForegroundColor Yellow
            $ws.Dispose()
            Start-Sleep -Seconds 30
            continue
        }

        # Start session
        $startCmd = '{"command":"startSession","commandId":1,"sessionId":"","eventId":""}'
        $startBytes = [System.Text.Encoding]::UTF8.GetBytes($startCmd)
        $seg = [System.ArraySegment[byte]]::new($startBytes)
        $null = $ws.SendAsync($seg, [System.Net.WebSockets.WebSocketMessageType]::Text, $true, $cts.Token).Wait(5000)

        # Subscription: cameras + event types (analysis)
        $camIds = @($cameras | ForEach-Object { $_.cameraId } | Select-Object -Unique)
        $evIds = @($cameras | ForEach-Object { $_.eventTypeId } | Where-Object { $_ } | Select-Object -Unique)
        if (-not $evIds) { $evIds = @("*") }
        $filter = @{
            modifier     = "include"
            resourceTypes = @("cameras")
            sourceIds    = @($camIds)
            eventTypes   = @($evIds)
        }
        $subCmd = @{ command = "addSubscription"; commandId = 2; filters = @($filter) } | ConvertTo-Json -Depth 5 -Compress
        $subBytes = [System.Text.Encoding]::UTF8.GetBytes($subCmd)
        $seg2 = [System.ArraySegment[byte]]::new($subBytes)
        $null = $ws.SendAsync($seg2, [System.Net.WebSockets.WebSocketMessageType]::Text, $true, $cts.Token).Wait(5000)

        # Subscription: IO (inputs/outputs) for state
        $ioIds = @($ioState.Keys)
        if ($ioIds.Count -gt 0) {
            $filterIo = @{
                modifier      = "include"
                resourceTypes = @("inputs", "outputs")
                sourceIds     = @($ioIds)
                eventTypes    = @("*")
            }
            $subCmdIo = @{ command = "addSubscription"; commandId = 3; filters = @($filterIo) } | ConvertTo-Json -Depth 5 -Compress
            $segIoBytes = [System.Text.Encoding]::UTF8.GetBytes($subCmdIo)
            $segIo = [System.ArraySegment[byte]]::new($segIoBytes)
            $null = $ws.SendAsync($segIo, [System.Net.WebSockets.WebSocketMessageType]::Text, $true, $cts.Token).Wait(5000)
        }

        # Plan B: subscribe to user-defined events (Alarm active / Alarm inactive)
        if ($useAlarmEvents) {
            $allAlarmEventTypes = @($alarmActiveEventTypeIds) + @($alarmInactiveEventTypeIds)
            $filterAlarm = @{
                modifier      = "include"
                resourceTypes = @("*")
                sourceIds     = @("*")
                eventTypes    = $allAlarmEventTypes
            }
            $alarmCmd = @{ command = "addSubscription"; commandId = 33; filters = @($filterAlarm) } | ConvertTo-Json -Depth 5 -Compress
            $alarmBytes = [System.Text.Encoding]::UTF8.GetBytes($alarmCmd)
            $segAlarm = [System.ArraySegment[byte]]::new($alarmBytes)
            $null = $ws.SendAsync($segAlarm, [System.Net.WebSockets.WebSocketMessageType]::Text, $true, $cts.Token).Wait(5000)
        }

        # getState to get current IO status
        $getStateCmd = '{"command":"getState","commandId":4}'
        $stateBytes = [System.Text.Encoding]::UTF8.GetBytes($getStateCmd)
        $segState = [System.ArraySegment[byte]]::new($stateBytes)
        $null = $ws.SendAsync($segState, [System.Net.WebSockets.WebSocketMessageType]::Text, $true, $cts.Token).Wait(5000)

        $lastTokenRefresh = [DateTime]::UtcNow
        $connectedSince = [DateTime]::UtcNow
        $msg = "WebSocket opened, subscriptions active. Waiting for events..."
        Write-Log $msg "INFO"
        Write-Host $msg -ForegroundColor Green
        if ($ioState.Keys.Count -gt 0) {
            $ioMsg = "Subscribed to IO (outputs): $($ioState.Keys -join ', ')"
            Write-Log $ioMsg "INFO"
            Write-Host "  $ioMsg" -ForegroundColor DarkGray
        }

        while ($run -and $ws.State -eq "Open") {
            # Refresh token before expiration
            $secLeft = ($Script:MilestoneTokenExpiresAt - [DateTime]::UtcNow).TotalSeconds
            if ($secLeft -lt $RefreshBeforeSeconds) {
                $null = Get-MilestoneToken -RefreshBeforeSeconds $RefreshBeforeSeconds
                $lastTokenRefresh = [DateTime]::UtcNow
                Write-Log "Token refreshed." "INFO"
                Write-Host "Token refreshed." -ForegroundColor Gray
            }

            # ReceiveAsync waits indefinitely for messages - WebSocket should stay open
            $segRecv = [System.ArraySegment[byte]]::new($buffer)
            $result = $ws.ReceiveAsync($segRecv, $cts.Token)
            
            # Wait for message (indefinitely, but check token refresh every 30 seconds)
            $lastTokenCheck = [DateTime]::UtcNow
            while (-not $result.IsCompleted -and $run -and $ws.State -eq "Open") {
                Start-Sleep -Milliseconds 500
                
                # Check token refresh even while waiting for messages
                $now = [DateTime]::UtcNow
                if (($now - $lastTokenCheck).TotalSeconds -ge 30) {
                    $lastTokenCheck = $now
                    $secLeft = ($Script:MilestoneTokenExpiresAt - $now).TotalSeconds
                    if ($secLeft -lt $RefreshBeforeSeconds) {
                        $null = Get-MilestoneToken -RefreshBeforeSeconds $RefreshBeforeSeconds
                        Write-Log "Token refreshed (while waiting for messages)." "INFO"
                        Write-Host "Token refreshed (while waiting for messages)." -ForegroundColor Gray
                    }
                }
            }
            
            if ($result.IsFaulted) {
                $errorMsg = "WebSocket error: $($result.Exception.Message)"
                Write-Log $errorMsg "ERROR"
                Write-Host $errorMsg -ForegroundColor Red
                break
            }
            if ($result.IsCanceled) {
                Write-Log "WebSocket canceled." "WARN"
                Write-Host "WebSocket canceled." -ForegroundColor Yellow
                break
            }
            if (-not $result.IsCompleted) {
                # Timeout or other - continue waiting
                continue
            }
            
            $recv = $result.Result
            if ($recv.MessageType -eq "Close") {
                Write-Log "WebSocket closed by server." "WARN"
                Write-Host "WebSocket closed by server." -ForegroundColor Yellow
                break
            }
            $text = [System.Text.Encoding]::UTF8.GetString($buffer, 0, $recv.Count)
            try {
                $msg = $text | ConvertFrom-Json
                if ($msg.events) {
                    foreach ($ev in $msg.events) {
                        $src = $ev.source
                        $eventMsg = "Event: source=$src type=$($ev.type)"
                        Write-Log $eventMsg "INFO"
                        Write-Host "  $eventMsg" -ForegroundColor DarkGray
                        $evType = $ev.type
                        $evTypeLow = $evType.ToString().ToLowerInvariant()
                        if ($useAlarmEvents) {
                            # Check if this is an alarm active event
                            foreach ($activeId in $alarmActiveEventTypeIds) {
                                if ($evTypeLow -eq $activeId.ToString().ToLowerInvariant()) {
                                    $script:alarmActive = $true
                                    $alarmMsg = "Alarm ACTIVE (user-defined event: $activeId)."
                                    Write-Log $alarmMsg "INFO"
                                    Write-Host "  $alarmMsg" -ForegroundColor Green
                                    break
                                }
                            }
                            # Check if this is an alarm inactive event
                            foreach ($inactiveId in $alarmInactiveEventTypeIds) {
                                if ($evTypeLow -eq $inactiveId.ToString().ToLowerInvariant()) {
                                    $script:alarmActive = $false
                                    $alarmMsg = "Alarm INACTIVE (user-defined event: $inactiveId)."
                                    Write-Log $alarmMsg "INFO"
                                    Write-Host "  $alarmMsg" -ForegroundColor Gray
                                    break
                                }
                            }
                        }
                        foreach ($kid in $ioState.Keys) {
                            if ($src -like "*$kid*") { Write-Host "  [IO candidate] source=$src" -ForegroundColor Yellow }
                        }
                        # Is this an analysis event from a configured camera?
                        $camGuid = $null
                        if ($src -match "cameras/([a-fA-F0-9\-]+)") { $camGuid = $Matches[1].ToLowerInvariant() }
                        $match = $cameras | Where-Object {
                            $_.cameraId.ToString().ToLowerInvariant() -eq $camGuid -and
                            ($_.eventTypeId.ToString().ToLowerInvariant() -eq $evTypeLow -or $_.eventTypeId -eq "" -or -not $_.eventTypeId)
                        }
                        if ($match) {
                            foreach ($m in $match) {
                                $ioId = $m.ioSourceId.ToString().ToLowerInvariant()
                                # Check if this camera uses user-defined events or IO
                                $cameraUsesUserDefined = ($m.ioType -eq "userDefined" -or ($m.alarmActiveEventTypeId -and $m.alarmInactiveEventTypeId))
                                
                                # If requireIoActive = false: always send. Otherwise: require IO/Plan B to be active
                                if (-not $requireIoActive) {
                                    $shouldSend = $true
                                } else {
                                    if ($cameraUsesUserDefined) {
                                        # For user-defined events: check if alarm is active (global state)
                                        $shouldSend = $script:alarmActive
                                    } else {
                                        # For IO: check if IO is active
                                        $ioIsActive = $ioState.ContainsKey($ioId) -and $ioState[$ioId]
                                        $shouldSend = $ioIsActive
                                    }
                                }
                                if ($shouldSend) {
                                    $ioStatus = if (-not $requireIoActive) { "no IO requirement" } elseif ($cameraUsesUserDefined) { if ($script:alarmActive) { "user-defined alarm active" } else { "user-defined alarm inactive" } } else { if ($ioState.ContainsKey($ioId) -and $ioState[$ioId]) { "IO active" } else { "IO inactive" } }
                                    $triggerMsg = "Trigger: $($m.cameraName) + $ioStatus -> webhook $($m.webhookUrl)"
                                    Write-Log $triggerMsg "INFO"
                                    Write-Host $triggerMsg -ForegroundColor Green
                                    $timestamp = if ($ev.time) { $ev.time } else { [DateTime]::UtcNow.ToString("o") }
                                    $payload = New-MilestoneEventPayload -CameraId $m.cameraId -CameraName $m.cameraName -MessageId $evType -Timestamp $timestamp
                                    $null = Send-Webhook -Url $m.webhookUrl -Payload $payload
                                    Write-Log "Webhook sent successfully to $($m.webhookUrl)" "INFO"
                                    Write-Host "  Webhook sent successfully" -ForegroundColor DarkGreen
                                } else {
                                    $ioStatus = if ($cameraUsesUserDefined) { if ($script:alarmActive) { "user-defined alarm active" } else { "user-defined alarm inactive" } } else { if ($ioState.ContainsKey($ioId) -and $ioState[$ioId]) { "IO active" } else { "IO inactive" } }
                                    $skipMsg = "Skipped: $($m.cameraName) - analysis event but $ioStatus (webhook requires active alarm)"
                                    Write-Log $skipMsg "INFO"
                                    Write-Host "  $skipMsg" -ForegroundColor DarkGray
                                }
                            }
                        }
                        # Update IO state: input/output "open"/active = true, "closed"/inactive = false
                        $isActive = $true
                        if ($ev.data -and $ev.data.description) {
                            $d = $ev.data.description.ToString().ToLowerInvariant()
                            if ($d -match "closed|inactive|off|stängd") { $isActive = $false }
                        }
                        if ($src -match "inputs/([a-fA-F0-9\-]+)") {
                            $ioId = $Matches[1].ToLowerInvariant()
                            if ($ioState.ContainsKey($ioId)) { $ioState[$ioId] = $isActive }
                        }
                        if ($src -match "outputs/([a-fA-F0-9\-]+)") {
                            $ioId = $Matches[1].ToLowerInvariant()
                            if ($ioState.ContainsKey($ioId)) {
                                $ioState[$ioId] = $isActive
                                Write-Host "  IO: $ioId = $isActive" -ForegroundColor DarkGray
                            }
                        }
                    }
                }
                if ($msg.states) {
                    Write-Host "  States (getState response): $($msg.states.Count) items" -ForegroundColor DarkGray
                    foreach ($st in $msg.states) {
                        $src = $st.source
                        Write-Host "    state source=$src type=$($st.type)" -ForegroundColor DarkGray
                        if ($src -match "inputs/([a-fA-F0-9\-]+)") {
                            $ioId = $Matches[1].ToLowerInvariant()
                            if ($ioState.ContainsKey($ioId)) { $ioState[$ioId] = $true }
                        }
                        if ($src -match "outputs/([a-fA-F0-9\-]+)") {
                            $ioId = $Matches[1].ToLowerInvariant()
                            if ($ioState.ContainsKey($ioId)) { $ioState[$ioId] = $true }
                        }
                    }
                }
            } catch {}
        }

        $ws.Dispose()
        if ($cts) { try { $cts.Cancel(); $cts.Dispose() } catch {} }
        
        # Log connection time and reason
        $minsConnected = if ($connectedSince) { ([DateTime]::UtcNow - $connectedSince).TotalMinutes } else { 0 }
        if ($minsConnected -ge 5) { 
            $script:reconnectDelaySec = 15
            $msg = "WebSocket disconnected after $([Math]::Round($minsConnected, 1)) minutes. Reconnecting in $reconnectDelaySec s."
            Write-Log $msg "WARN"
            Write-Host $msg -ForegroundColor Yellow
        } else {
            $msg = "WebSocket disconnected after short time ($([Math]::Round($minsConnected, 1)) min). Reconnecting in $reconnectDelaySec s."
            Write-Log $msg "WARN"
            Write-Host $msg -ForegroundColor Yellow
        }
        
        Start-Sleep -Seconds $reconnectDelaySec
        if ($reconnectDelaySec -lt $reconnectDelayMax) { $script:reconnectDelaySec = [Math]::Min($reconnectDelayMax, $reconnectDelaySec + 15) }
    } catch {
        $errorMsg = "Error in WebSocket loop: $($_.Exception.Message)"
        Write-Log $errorMsg "ERROR"
        Write-Log "Stack trace: $($_.ScriptStackTrace)" "ERROR"
        Write-Host $errorMsg -ForegroundColor Red
        Write-Host "Reconnecting in $reconnectDelaySec s." -ForegroundColor Yellow
        Start-Sleep -Seconds $reconnectDelaySec
        if ($reconnectDelaySec -lt $reconnectDelayMax) { $script:reconnectDelaySec = [Math]::Min($reconnectDelayMax, $reconnectDelaySec + 15) }
    }
}

Write-Log "Bridge stopped." "INFO"
Write-Host "Stopped." -ForegroundColor Cyan

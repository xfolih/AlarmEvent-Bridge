# Interaktiv konfiguration: valj kameror, handelsetyper, IO och webhook.
# Sparar till WebhookConfig.json. Kora: .\Setup-MilestoneWebhookConfig.ps1

$ErrorActionPreference = "Stop"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $ScriptDir

# Ladda API-hjalpare
. .\MilestoneApi.ps1

# Lasa eller fraga efter anslutning
$configPath = Join-Path $ScriptDir "WebhookConfig.json"
$credPath = Join-Path $ScriptDir "Credentials.ps1"

if (Test-Path $credPath) {
    . $credPath
    $Script:MilestoneApiBaseUrl = $MilestoneApiBaseUrl
    $Script:MilestoneUsername = $MilestoneUsername
    $Script:MilestonePassword = $MilestonePassword
} else {
    Write-Host "Forsta gangen: ange anslutning till XProtect." -ForegroundColor Cyan
    $Script:MilestoneApiBaseUrl = Read-Host "API bas-URL (t.ex. https://localhost)"
    $Script:MilestoneUsername = Read-Host "Anvandarnamn (t.ex. API)"
    $Script:MilestonePassword = Read-Host "Losenord" -AsSecureString
    $Script:MilestonePassword = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($Script:MilestonePassword))
    $credContent = @"
# Spara inte denna fil i versionshantering. Skapad av Setup-MilestoneWebhookConfig.ps1
`$MilestoneApiBaseUrl = "$Script:MilestoneApiBaseUrl"
`$MilestoneUsername = "$Script:MilestoneUsername"
`$MilestonePassword = "$Script:MilestonePassword"
"@
    Set-Content -Path $credPath -Value $credContent -Encoding UTF8
    Write-Host "Sparat till $credPath" -ForegroundColor Green
}

if ($Script:MilestoneApiBaseUrl -like "https://*") {
    [System.Net.ServicePointManager]::ServerCertificateValidationCallback = { $true }
    [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12
}

# Hamta token och verifiera
Write-Host "Ansluter till Milestone..." -ForegroundColor Yellow
$null = Get-MilestoneToken
Write-Host "Anslutning OK." -ForegroundColor Green
Write-Host ""

# Lasa befintlig config om den finns (som hashtable sa att Plan B-egenskaper kan sattas)
$globalConfig = @{ apiBaseUrl = $Script:MilestoneApiBaseUrl; cameras = @() }
if (Test-Path $configPath) {
    try {
        $loaded = Get-Content $configPath -Raw | ConvertFrom-Json
        $globalConfig = @{
            apiBaseUrl = $loaded.apiBaseUrl
            cameras    = @($loaded.cameras)
        }
        if (-not $globalConfig.cameras) { $globalConfig.cameras = @() }
        if ($loaded.alarmActiveEventTypeId) { $globalConfig.alarmActiveEventTypeId = $loaded.alarmActiveEventTypeId }
        if ($loaded.alarmInactiveEventTypeId) { $globalConfig.alarmInactiveEventTypeId = $loaded.alarmInactiveEventTypeId }
    } catch {
        $globalConfig.cameras = @()
    }
}

# Plan B: Anvandardefinierade handelser for larmstatus (en gang per konfiguration)
$usePlanB = $false
if ($globalConfig.alarmActiveEventTypeId -and $globalConfig.alarmInactiveEventTypeId) {
    Write-Host "Larmstatus styrs redan av anvandardefinierade handelser (Plan B)." -ForegroundColor Green
    $usePlanB = $true
} else {
    Write-Host "Ska larmstatus styras av anvandardefinierade handelser (Plan B)?" -ForegroundColor Cyan
    Write-Host "Pa manga anlaggningar skickar API:et inte utgangsstatus - da ar Plan B losningen." -ForegroundColor Gray
    Write-Host "Du skapar i Milestone t.ex. 'Larm aktiv' och 'Larm inaktiv' och regler som triggar dem vid utgång på/av." -ForegroundColor Gray
    $planBChoice = Read-Host "Anvand Plan B? (j/n)"
    if ($planBChoice -eq "j" -or $planBChoice -eq "J" -or $planBChoice -eq "ja") {
        $eventTypesForAlarm = @(Get-MilestoneEventTypes)
        if (-not $eventTypesForAlarm -or $eventTypesForAlarm.Count -eq 0) {
            Write-Host "Inga handelsetyper hittades. Skapa forst anvandardefinierade handelser i Milestone." -ForegroundColor Red
        } else {
            Write-Host "Handelsetyper (valj t.ex. Larm aktiv och Larm inaktiv):" -ForegroundColor Yellow
            $idx = 1
            foreach ($e in $eventTypesForAlarm) {
                Write-Host "  $idx. $($e.name) ($($e.id))"
                $idx++
            }
            $a = Read-Host "Nummer for handelsetyp 'Larm aktiv' (eller motsvarande)"
            $b = Read-Host "Nummer for handelsetyp 'Larm inaktiv' (eller motsvarande)"
            $na = 0; $nb = 0
            if ([int]::TryParse($a.Trim(), [ref]$na) -and $na -ge 1 -and $na -le $eventTypesForAlarm.Count -and [int]::TryParse($b.Trim(), [ref]$nb) -and $nb -ge 1 -and $nb -le $eventTypesForAlarm.Count) {
                $globalConfig.alarmActiveEventTypeId = $eventTypesForAlarm[$na - 1].id
                $globalConfig.alarmInactiveEventTypeId = $eventTypesForAlarm[$nb - 1].id
                $usePlanB = $true
                Write-Host "Plan B sparad: Larm aktiv = $($eventTypesForAlarm[$na - 1].name), Larm inaktiv = $($eventTypesForAlarm[$nb - 1].name)" -ForegroundColor Green
            } else {
                Write-Host "Ogiltigt val. Du kan ange Plan B senare i WebhookConfig.json." -ForegroundColor Yellow
            }
        }
    }
}
Write-Host ""

function Show-Menu {
    param([string]$Title, [array]$Items, [string]$AddOption = "Avbryt")
    $i = 1
    foreach ($item in $Items) {
        $label = if ($item.name) { $item.name } elseif ($item.displayName) { $item.displayName } else { $item.id }
        Write-Host "  $i. $label"
        $i++
    }
    if ($AddOption -eq "Avbryt") {
        Write-Host "  0. Avbryt"
    } else {
        Write-Host "  0. $AddOption"
    }
    return $i
}

function Read-Selection {
    param([int]$Max, [string]$Prompt = "Val (nummer)")
    $n = -1
    while ($n -lt 0 -or $n -gt $Max) {
        $s = Read-Host $Prompt
        if (-not [int]::TryParse($s, [ref]$n)) { $n = -1 }
    }
    return $n
}

# Huvudloop: lagg till kameror tills anvandaren ar klar
do {
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "  Kamera-regel: Analys + IO aktiv -> Webhook" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host ""

    # 1) Lista kameror (tvinga till array sa att .Count fungerar vid en kamera)
    $cameras = @(Get-MilestoneCameras)
    if (-not $cameras -or $cameras.Count -eq 0) {
        Write-Host "Inga kameror hittades. Kontrollera API-behorighet och att det finns kameror i XProtect." -ForegroundColor Red
        break
    }
    Write-Host "Kameror:" -ForegroundColor Yellow
    $idx = 1
    foreach ($c in $cameras) {
        Write-Host "  $idx. $($c.name) ($($c.id))"
        $idx++
    }
    $camChoice = Read-Host "Valj kamera (nummer)"
    $camNum = 0
    $camCount = $cameras.Count
    if (-not [int]::TryParse($camChoice.Trim(), [ref]$camNum) -or $camNum -lt 1 -or $camNum -gt $camCount) {
        Write-Host "Ogiltigt val. Ange ett nummer mellan 1 och $camCount." -ForegroundColor Red
        continue
    }
    $selectedCamera = $cameras[$camNum - 1]
    Write-Host "Vald: $($selectedCamera.name)" -ForegroundColor Green
    Write-Host ""

    # 2) Lista handelsetyper (tvinga till array)
    $eventTypes = @(Get-MilestoneEventTypes)
    if (-not $eventTypes -or $eventTypes.Count -eq 0) {
        Write-Host "Inga handelsetyper hittades. Anvand standard/analys-typ." -ForegroundColor Yellow
        $eventTypeId = Read-Host "Ange handelsetyp GUID (eller lamna tom for att skippa)"
        $eventTypeName = "Custom"
    } else {
        Write-Host "Handelsetyper:" -ForegroundColor Yellow
        $idx = 1
        foreach ($e in $eventTypes) {
            Write-Host "  $idx. $($e.name) ($($e.id))"
            $idx++
        }
        $evChoice = Read-Host "Valj handelsetyp (nummer)"
        $evNum = 0
        if (-not [int]::TryParse($evChoice.Trim(), [ref]$evNum) -or $evNum -lt 1 -or $evNum -gt $eventTypes.Count) {
            Write-Host "Ogiltigt val, hoppar over kamera." -ForegroundColor Red
            continue
        }
        $selectedEvent = $eventTypes[$evNum - 1]
        $eventTypeId = $selectedEvent.id
        $eventTypeName = $selectedEvent.name
        Write-Host "Vald: $eventTypeName" -ForegroundColor Green
    }
    Write-Host ""

    # 3) Larmstatus: Plan B (anvandardefinierade handelser) eller ingang/utgang (IO)
    if ($usePlanB) {
        Write-Host "Larmstatus: Plan B (anvandardefinierade handelser Larm aktiv / Larm inaktiv)." -ForegroundColor Green
        $ioId = ""
        $ioName = "Plan B (anvandardefinierade handelser)"
        $ioType = "planB"
    } else {
        $inputs = Get-MilestoneInputs
        $outputs = Get-MilestoneOutputs
        $ioList = @()
        foreach ($i in @($inputs)) { $ioList += [PSCustomObject]@{ id = $i.id; name = $i.name; type = "input" } }
        foreach ($o in @($outputs)) { $ioList += [PSCustomObject]@{ id = $o.id; name = $o.name; type = "output" } }
        $ioList = @($ioList)
        if (-not $ioList -or $ioList.Count -eq 0) {
            Write-Host "Inga ingangar/utgangar hittades via API." -ForegroundColor Yellow
            Write-Host "Valj Plan B vid nasta korning (anvandardefinierade handelser) eller ange IO-GUID manuellt." -ForegroundColor Gray
            Write-Host "I Milestone: hall CTRL och klicka pa utgangen/ingangen sa ser du dess ID." -ForegroundColor Gray
            $ioId = Read-Host "Ange IO-enhetens GUID (lamna tom for att skippa)"
            if ($ioId) { $ioId = $ioId.Trim().ToLowerInvariant() }
            $ioName = "Manuell"
            $ioType = "input"
        } else {
            Write-Host 'Ingangar och utgangar (IO) – valj vad som styr ''larm tillkopplat'':' -ForegroundColor Yellow
            $idx = 1
            foreach ($io in $ioList) {
                Write-Host "  $idx. [$($io.type)] $($io.name) ($($io.id))"
                $idx++
            }
            $ioChoice = Read-Host "Valj IO (nummer)"
            $ioNum = 0
            if (-not [int]::TryParse($ioChoice.Trim(), [ref]$ioNum) -or $ioNum -lt 1 -or $ioNum -gt $ioList.Count) {
                Write-Host "Ogiltigt val, hoppar over kamera." -ForegroundColor Red
                continue
            }
            $selectedIo = $ioList[$ioNum - 1]
            $ioId = $selectedIo.id
            $ioName = $selectedIo.name
            $ioType = $selectedIo.type
            Write-Host "Vald: [$ioType] $ioName" -ForegroundColor Green
        }
    }
    Write-Host ""

    # 4) Webhook: fardiga eller manuell URL
    $webhooks = Get-MilestoneWebhooks
    $webhookUrl = ""
    if ($webhooks -and $webhooks.Count -gt 0) {
        Write-Host "Befintliga webhooks i Milestone:" -ForegroundColor Yellow
        $idx = 1
        foreach ($w in $webhooks) {
            Write-Host "  $idx. $($w.name) -> $($w.url)"
            $idx++
        }
        Write-Host "  0. Skriv in egen URL"
        $whChoice = Read-Host "Valj webhook (nummer) eller 0 for egen URL"
        $whNum = -1
        if ([int]::TryParse($whChoice, [ref]$whNum) -and $whNum -ge 1 -and $whNum -le $webhooks.Count) {
            $webhookUrl = $webhooks[$whNum - 1].url
        }
    }
    if (-not $webhookUrl) {
        $webhookUrl = Read-Host "Webhook-URL (t.ex. https://larmcentralen.example.com/webhook)"
    }
    if ([string]::IsNullOrWhiteSpace($webhookUrl)) {
        Write-Host "Ingen URL angiven, hoppar over kamera." -ForegroundColor Red
        continue
    }
    Write-Host "Webhook: $webhookUrl" -ForegroundColor Green
    Write-Host ""

    # Spara till config
    $entry = [PSCustomObject]@{
        cameraId       = $selectedCamera.id
        cameraName     = $selectedCamera.name
        eventTypeId    = $eventTypeId
        eventTypeName  = $eventTypeName
        ioSourceId     = $ioId
        ioSourceName   = $ioName
        ioType         = $ioType
        webhookUrl     = $webhookUrl
    }
    $globalConfig.cameras += $entry
    Write-Host ('Tillagd: ' + $selectedCamera.name + ' -> ' + $webhookUrl) -ForegroundColor Green
    Write-Host ""

    $more = Read-Host 'Lagg till en till kamera? (j/n)'
} while ($more -eq 'j' -or $more -eq 'J' -or $more -eq 'ja')

# Skriv config (utan losenord)
$save = @{
    apiBaseUrl = $globalConfig.apiBaseUrl
    cameras    = @($globalConfig.cameras)
}
if ($globalConfig.alarmActiveEventTypeId) { $save.alarmActiveEventTypeId = $globalConfig.alarmActiveEventTypeId }
if ($globalConfig.alarmInactiveEventTypeId) { $save.alarmInactiveEventTypeId = $globalConfig.alarmInactiveEventTypeId }
$save | ConvertTo-Json -Depth 5 | Set-Content -Path $configPath -Encoding UTF8
Write-Host ('Konfiguration sparad till ' + $configPath) -ForegroundColor Green
Write-Host ('Antal kameror: ' + $globalConfig.cameras.Count) -ForegroundColor Cyan
Write-Host 'Kor da: .\Start-MilestoneWebhookBridge.ps1' -ForegroundColor Cyan

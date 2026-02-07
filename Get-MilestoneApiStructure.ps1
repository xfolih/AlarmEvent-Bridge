# Skriver ut vilken struktur Milestone Config API returnerar (sites, recordingservers, resources).
# Kor detta och spara utskriften sa vi kan hitta ratt sokvag for utganger.
# Kora: .\Get-MilestoneApiStructure.ps1

$ErrorActionPreference = "Stop"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $ScriptDir

. .\MilestoneApi.ps1
$credPath = Join-Path $ScriptDir "Credentials.ps1"
if (Test-Path $credPath) {
    . $credPath
    $Script:MilestoneApiBaseUrl = $MilestoneApiBaseUrl
    $Script:MilestoneUsername = $MilestoneUsername
    $Script:MilestonePassword = $MilestonePassword
} else {
    $Script:MilestoneApiBaseUrl = Read-Host "API bas-URL (t.ex. https://localhost)"
    $Script:MilestoneUsername = Read-Host "Anvandarnamn"
    $Script:MilestonePassword = Read-Host "Losenord" -AsSecureString
    $Script:MilestonePassword = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($Script:MilestonePassword))
}
if ($Script:MilestoneApiBaseUrl -like "https://*") {
    [System.Net.ServicePointManager]::ServerCertificateValidationCallback = { $true }
    [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12
}

Write-Host "Hamtar struktur fran Milestone Config API..." -ForegroundColor Cyan
$null = Get-MilestoneToken

# 1) Sites
Write-Host "`n=== GET /sites ===" -ForegroundColor Yellow
try {
    $sites = Invoke-MilestoneConfigApi -Path "/sites"
    $sites | ConvertTo-Json -Depth 5
} catch { Write-Host "Fel: $_" }

# 2) Recording servers (via site eller direkt)
$rsId = $null
Write-Host "`n=== GET /recordingservers ===" -ForegroundColor Yellow
try {
    $rec = Invoke-MilestoneConfigApi -Path "/recordingservers"
    $rec | ConvertTo-Json -Depth 5
    if ($rec.array -and $rec.array.Count -gt 0) { $rsId = $rec.array[0].id }
} catch { Write-Host "Fel: $_" }
if (-not $rsId -and $sites.array -and $sites.array.Count -gt 0) {
    Write-Host "`n=== GET /sites/{id}/recordingservers ===" -ForegroundColor Yellow
    try {
        $rec = Invoke-MilestoneConfigApi -Path "/sites/$($sites.array[0].id)/recordingservers"
        $rec | ConvertTo-Json -Depth 5
        if ($rec.array -and $rec.array.Count -gt 0) { $rsId = $rec.array[0].id }
    } catch { Write-Host "Fel: $_" }
}

# 3) Hardware-lista (direkt)
if ($rsId) {
    Write-Host "`n=== GET /recordingservers/$rsId/hardware ===" -ForegroundColor Yellow
    try {
        $hwList = Invoke-MilestoneConfigApi -Path "/recordingservers/$rsId/hardware"
        $hwList | ConvertTo-Json -Depth 6
        $firstHwId = $null
        if ($hwList.array -and $hwList.array.Count -gt 0) {
            $firstHwId = $hwList.array[0].id
            Write-Host "Forsta hardware id: $firstHwId" -ForegroundColor Green
        }
    } catch { Write-Host "Fel: $_" -ForegroundColor Red }
    if ($firstHwId) {
        Write-Host "`n=== GET /recordingservers/$rsId/hardware/$firstHwId/outputs ===" -ForegroundColor Yellow
        try {
            $outRes = Invoke-MilestoneConfigApi -Path "/recordingservers/$rsId/hardware/$firstHwId/outputs"
            if ($outRes.array) { Write-Host "Utgangar: $($outRes.array.Count) st" -ForegroundColor Green }
            $outRes | ConvertTo-Json -Depth 6
        } catch { Write-Host "Fel: $_" -ForegroundColor Red }
        Write-Host "`n=== GET /recordingservers/$rsId/hardware/$firstHwId?resources ===" -ForegroundColor Yellow
        try {
            $childRes = Invoke-MilestoneConfigApi -Path "/recordingservers/$rsId/hardware/$firstHwId`?resources"
            if ($childRes.resources) {
                foreach ($cr in $childRes.resources) {
                    $cnt = if ($cr.array) { $cr.array.Count } else { 0 }
                    Write-Host "  child type: $($cr.type)  antal: $cnt"
                }
            }
            $childRes | ConvertTo-Json -Depth 8
        } catch { Write-Host "Fel: $_" -ForegroundColor Red }
    }
    Write-Host "`n=== GET /recordingservers/$rsId?resources ===" -ForegroundColor Yellow
    try {
        $res = Invoke-MilestoneConfigApi -Path "/recordingservers/$rsId`?resources"
        Write-Host "Resurstyper som finns:" -ForegroundColor Green
        if ($res.resources) {
            foreach ($r in $res.resources) {
                $ty = $r.type
                $count = if ($r.array) { $r.array.Count } else { 0 }
                Write-Host "  - type: $ty  antal: $count"
            }
            $res | ConvertTo-Json -Depth 8
        } else {
            $res | ConvertTo-Json -Depth 8
        }
        if ($res.resources) {
            foreach ($r in $res.resources) {
                if (($r.type -match "hardware|device") -and $r.array -and $r.array.Count -gt 0) {
                    $hwId = $r.array[0].id
                    $hwName = $r.array[0].displayName
                    Write-Host "`n=== GET /recordingservers/$rsId/$($r.type)/$hwId?resources (forst: $hwName) ===" -ForegroundColor Yellow
                    try {
                        $child = Invoke-MilestoneConfigApi -Path "/recordingservers/$rsId/$($r.type)/$hwId`?resources"
                        if ($child.resources) {
                            foreach ($cr in $child.resources) {
                                Write-Host "  child type: $($cr.type)  antal: $(if ($cr.array) { $cr.array.Count } else { 0 })"
                            }
                            $child | ConvertTo-Json -Depth 8
                        } else {
                            $child | ConvertTo-Json -Depth 8
                        }
                    } catch {
                        Write-Host "Fel: $_"
                    }
                }
            }
        }
    } catch { Write-Host "Fel: $_" }
}

Write-Host "`nKlart. Kopiera utskriften (type + resources) om du ska rapportera tillbaka." -ForegroundColor Cyan

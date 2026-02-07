# Milestone API helper: token, refresh, Config API calls
# Dot-source this file: . .\MilestoneApi.ps1
# Then set $Script:MilestoneApiBaseUrl, $Script:MilestoneUsername, $Script:MilestonePassword
# and call Get-MilestoneToken, Invoke-MilestoneConfigApi

$ErrorActionPreference = "Stop"

# Script-level token cache (caller sets these before first Get-MilestoneToken)
if (-not $Script:MilestoneApiBaseUrl) { $Script:MilestoneApiBaseUrl = "https://localhost" }
if (-not $Script:MilestoneUsername)  { $Script:MilestoneUsername = "API" }
if (-not $Script:MilestonePassword)  { $Script:MilestonePassword = "" }
$Script:MilestoneToken = $null
$Script:MilestoneTokenExpiresAt = $null

function Get-MilestoneToken {
    param(
        [int]$RefreshBeforeSeconds = 300
    )
    $now = [DateTime]::UtcNow
    if ($Script:MilestoneToken -and $Script:MilestoneTokenExpiresAt -and ($Script:MilestoneTokenExpiresAt - $now).TotalSeconds -gt $RefreshBeforeSeconds) {
        return $Script:MilestoneToken
    }
    $idpUrl = $Script:MilestoneApiBaseUrl.TrimEnd("/") + "/API/IDP/connect/token"
    if ($Script:MilestoneApiBaseUrl -like "https://*") {
        [System.Net.ServicePointManager]::ServerCertificateValidationCallback = { $true }
        [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12
    }
    $body = @{
        grant_type = "password"
        username   = $Script:MilestoneUsername
        password   = $Script:MilestonePassword
        client_id  = "GrantValidatorClient"
    }
    $r = Invoke-RestMethod -Uri $idpUrl -Method Post -ContentType "application/x-www-form-urlencoded" -Body $body
    $Script:MilestoneToken = $r.access_token
    $Script:MilestoneTokenExpiresAt = $now.AddSeconds([int]$r.expires_in)
    return $Script:MilestoneToken
}

function Invoke-MilestoneConfigApi {
    param(
        [string]$Method = "GET",
        [string]$Path,
        [object]$Body = $null
    )
    $token = Get-MilestoneToken
    $base = $Script:MilestoneApiBaseUrl.TrimEnd("/") + "/api/rest/v1"
    $uri = $base + $Path
    $headers = @{ Authorization = "Bearer $token" }
    $params = @{ Uri = $uri; Method = $Method; Headers = $headers }
    if ($Body) { $params.Body = ($Body | ConvertTo-Json -Depth 10); $params.ContentType = "application/json" }
    return Invoke-RestMethod @params
}

function Get-MilestoneCameras {
    $all = @()
    try {
        $sites = Invoke-MilestoneConfigApi -Path "/sites"
        if ($sites.array) {
            foreach ($site in $sites.array) {
                $siteId = $site.id
                try {
                    $rec = Invoke-MilestoneConfigApi -Path "/sites/$siteId/recordingservers"
                    if ($rec.array) {
                        foreach ($rs in $rec.array) {
                            $rsId = $rs.id
                            try {
                                $hw = Invoke-MilestoneConfigApi -Path "/recordingservers/$rsId`?resources"
                                if ($hw.resources) {
                                    foreach ($r in $hw.resources) {
                                        if ($r.type -eq "cameras" -and $r.array) {
                                            foreach ($c in $r.array) {
                                                $all += [PSCustomObject]@{ id = $c.id; name = $c.displayName; siteId = $siteId; recordingServerId = $rsId }
                                            }
                                        }
                                    }
                                }
                            } catch {}
                        }
                    }
                } catch {}
            }
        }
    } catch {}
    if ($all.Count -eq 0) {
        try {
            $rec = Invoke-MilestoneConfigApi -Path "/recordingservers"
            if ($rec.array) {
                foreach ($rs in $rec.array) {
                    try {
                        $hw = Invoke-MilestoneConfigApi -Path "/recordingservers/$($rs.id)?resources"
                        if ($hw.resources) {
                            foreach ($r in $hw.resources) {
                                if ($r.type -eq "cameras" -and $r.array) {
                                    foreach ($c in $r.array) {
                                        $all += [PSCustomObject]@{ id = $c.id; name = $c.displayName; siteId = ""; recordingServerId = $rs.id }
                                    }
                                }
                            }
                        }
                    } catch {}
                }
            }
        } catch {}
    }
    if ($all.Count -eq 0) {
        try {
            $cam = Invoke-MilestoneConfigApi -Path "/cameras"
            if ($cam.array) {
                foreach ($c in $cam.array) { $all += [PSCustomObject]@{ id = $c.id; name = $c.displayName; siteId = ""; recordingServerId = "" } }
            }
        } catch {}
    }
    return $all
}

function Get-MilestoneEventTypes {
    $all = @()
    try {
        $et = Invoke-MilestoneConfigApi -Path "/eventTypes"
        if ($et.array) {
            foreach ($e in $et.array) {
                $name = if ($e.displayName) { $e.displayName } elseif ($e.name) { $e.name } else { $e.id }
                $all += [PSCustomObject]@{ id = $e.id; name = $name }
            }
        }
    } catch {}
    return $all
}

function Get-MilestoneInputs {
    $all = @()
    try {
        $ig = Invoke-MilestoneConfigApi -Path "/inputGroups"
        if ($ig.array) {
            foreach ($g in $ig.array) {
                try {
                    $inputs = Invoke-MilestoneConfigApi -Path "/inputGroups/$($g.id)/inputs"
                    if ($inputs.array) {
                        foreach ($i in $inputs.array) {
                            $name = if ($i.displayName) { $i.displayName } elseif ($i.name) { $i.name } else { $i.id }
                            $all += [PSCustomObject]@{ id = $i.id; name = $name; type = "input"; groupId = $g.id }
                        }
                    }
                } catch {}
            }
        }
    } catch {}
    if ($all.Count -eq 0) {
        try {
            $sites = Invoke-MilestoneConfigApi -Path "/sites"
            if ($sites.array) {
                foreach ($site in $sites.array) {
                    try {
                        $res = Invoke-MilestoneConfigApi -Path "/sites/$($site.id)/recordingservers"
                        if ($res.array) {
                            foreach ($rs in $res.array) {
                                try {
                                    $hw = Invoke-MilestoneConfigApi -Path "/recordingservers/$($rs.id)`?resources"
                                    if ($hw.resources) {
                                        foreach ($r in $hw.resources) {
                                            if (($r.type -eq "inputs" -or $r.type -eq "input") -and $r.array) {
                                                foreach ($i in $r.array) {
                                                    $name = if ($i.displayName) { $i.displayName } elseif ($i.name) { $i.name } else { $i.id }
                                                    $all += [PSCustomObject]@{ id = $i.id; name = $name; type = "input"; groupId = "" }
                                                }
                                            }
                                        }
                                    }
                                } catch {}
                            }
                        }
                    } catch {}
                }
            }
        } catch {}
    }
    return $all
}

function Get-MilestoneOutputs {
    $all = @()
    $seenIds = @{}
    try {
        $recList = $null
        $sites = Invoke-MilestoneConfigApi -Path "/sites"
        if ($sites.array -and $sites.array.Count -gt 0) {
            foreach ($site in $sites.array) {
                try {
                    $res = Invoke-MilestoneConfigApi -Path "/sites/$($site.id)/recordingservers"
                    if ($res.array) { $recList = $res.array; break }
                } catch {}
            }
        }
        if (-not $recList) {
            try {
                $rec = Invoke-MilestoneConfigApi -Path "/recordingservers"
                if ($rec.array) { $recList = $rec.array }
            } catch {}
        }
        if (-not $recList) { return $all }
        foreach ($rs in $recList) {
            $rsId = $rs.id
            try {
                $hwRoot = Invoke-MilestoneConfigApi -Path "/recordingservers/$rsId`?resources"
                foreach ($outPath in @("/outputs", "/recordingservers/$rsId/outputs", "/recordingServers/$rsId/outputs")) {
                    try {
                        $outList = Invoke-MilestoneConfigApi -Path $outPath
                        if ($outList.array) {
                            foreach ($o in $outList.array) {
                                if (-not $o -or $seenIds[$o.id]) { continue }
                                $seenIds[$o.id] = $true
                                $name = if ($o.displayName) { $o.displayName } elseif ($o.name) { $o.name } else { $o.id }
                                $all += [PSCustomObject]@{ id = $o.id; name = $name; type = "output"; groupId = "" }
                            }
                            if ($all.Count -gt 0) { break }
                        }
                    } catch {}
                }
                if ($hwRoot.resources) {
                    foreach ($r in $hwRoot.resources) {
                        $resType = $r.type
                        if ($resType -eq "outputs" -or $resType -eq "output") {
                            foreach ($outPath in @("/recordingservers/$rsId/$resType", "/recordingServers/$rsId/$resType")) {
                                try {
                                    $outList = Invoke-MilestoneConfigApi -Path $outPath
                                    if ($outList.array) {
                                        foreach ($o in $outList.array) {
                                            if (-not $o -or $seenIds[$o.id]) { continue }
                                            $seenIds[$o.id] = $true
                                            $name = if ($o.displayName) { $o.displayName } elseif ($o.name) { $o.name } else { $o.id }
                                            $all += [PSCustomObject]@{ id = $o.id; name = $name; type = "output"; groupId = "" }
                                        }
                                        break
                                    }
                                } catch {}
                            }
                        }
                        if ($resType -eq "hardware") {
                            $hwArray = @()
                            foreach ($basePath in @("/recordingservers/$rsId/hardware", "/recordingServers/$rsId/hardware")) {
                                try {
                                    $hardwareList = Invoke-MilestoneConfigApi -Path $basePath
                                    if ($hardwareList.array) { $hwArray = @($hardwareList.array); break }
                                    if ($hardwareList.data) { $hwArray = @($hardwareList.data); break }
                                    if ($hardwareList.resources) {
                                        foreach ($re in $hardwareList.resources) {
                                            if ($re.array) { $hwArray = @($hwArray) + @($re.array); break }
                                        }
                                        if ($hwArray.Count -gt 0) { break }
                                    }
                                } catch {}
                            }
                            foreach ($dev in $hwArray) {
                                $devId = $dev.id
                                if (-not $devId) { continue }
                                foreach ($base in @("/recordingservers/$rsId/hardware", "/recordingServers/$rsId/hardware")) {
                                    foreach ($outSubPath in @("$base/$devId/outputs", "$base/$devId/output", "/hardware/$devId/outputs")) {
                                    try {
                                        $outList = Invoke-MilestoneConfigApi -Path $outSubPath
                                        if ($outList.array) {
                                            foreach ($o in $outList.array) {
                                                if (-not $o -or $seenIds[$o.id]) { continue }
                                                $seenIds[$o.id] = $true
                                                $name = if ($o.displayName) { $o.displayName } elseif ($o.name) { $o.name } else { $o.id }
                                                $all += [PSCustomObject]@{ id = $o.id; name = $name; type = "output"; groupId = "" }
                                            }
                                            break
                                        }
                                        if ($outList.data -and (Get-Member -InputObject $outList.data -Name Count -ErrorAction SilentlyContinue)) {
                                            foreach ($o in $outList.data) {
                                                if (-not $o -or $seenIds[$o.id]) { continue }
                                                $seenIds[$o.id] = $true
                                                $name = if ($o.displayName) { $o.displayName } elseif ($o.name) { $o.name } else { $o.id }
                                                $all += [PSCustomObject]@{ id = $o.id; name = $name; type = "output"; groupId = "" }
                                            }
                                            break
                                        }
                                    } catch {}
                                }
                                if ($all.Count -gt 0) { continue }
                                try {
                                    $child = Invoke-MilestoneConfigApi -Path "$base/$devId`?resources"
                                        if ($child.resources) {
                                            foreach ($cr in $child.resources) {
                                                if (($cr.type -eq "outputs" -or $cr.type -eq "output") -and $cr.array) {
                                                    foreach ($o in $cr.array) {
                                                        if (-not $o -or $seenIds[$o.id]) { continue }
                                                        $seenIds[$o.id] = $true
                                                        $name = if ($o.displayName) { $o.displayName } elseif ($o.name) { $o.name } else { $o.id }
                                                        $all += [PSCustomObject]@{ id = $o.id; name = $name; type = "output"; groupId = "" }
                                                    }
                                                    break
                                                }
                                            }
                                        }
                                    } catch {}
                                }
                            }
                        }
                    }
                }
            } catch {}
        }
    } catch {}
    return $all
}

function Get-MilestoneWebhooks {
    $all = @()
    try {
        $wh = Invoke-MilestoneConfigApi -Path "/webhooks"
        if ($wh.array) {
            foreach ($w in $wh.array) {
                $name = if ($w.displayName) { $w.displayName } elseif ($w.name) { $w.name } else { $w.url }
                $all += [PSCustomObject]@{ id = $w.id; name = $name; url = $w.url }
            }
        }
    } catch {}
    try {
        $wh = Invoke-MilestoneConfigApi -Path "/webhookEndpoints"
        if ($wh.array) {
            foreach ($w in $wh.array) {
                $name = if ($w.displayName) { $w.displayName } elseif ($w.name) { $w.name } else { $w.url }
                $all += [PSCustomObject]@{ id = $w.id; name = $name; url = $w.url }
            }
        }
    } catch {}
    return $all
}

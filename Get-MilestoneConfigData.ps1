# Outputs camera, event and IO list as JSON to stdout.
# Used by the GUI. Call: .\Get-MilestoneConfigData.ps1
# Requires Credentials.ps1 to exist and MilestoneApi.ps1 to be in the same folder.

$ErrorActionPreference = "Stop"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $ScriptDir

. .\MilestoneApi.ps1
if (-not (Test-Path (Join-Path $ScriptDir "Credentials.ps1"))) {
    Write-Error "Credentials.ps1 missing. Configure connection in GUI first."
    exit 1
}
. (Join-Path $ScriptDir "Credentials.ps1")
$Script:MilestoneApiBaseUrl = $MilestoneApiBaseUrl
$Script:MilestoneUsername = $MilestoneUsername
$Script:MilestonePassword = $MilestonePassword

if ($Script:MilestoneApiBaseUrl -like "https://*") {
    [System.Net.ServicePointManager]::ServerCertificateValidationCallback = { $true }
    [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12
}

try {
    $token = Get-MilestoneToken
} catch {
    Write-Error "Could not get token: $($_.Exception.Message)"
    exit 1
}

$cameras = @(Get-MilestoneCameras | ForEach-Object { [PSCustomObject]@{ id = $_.id; name = $_.name } })
$eventTypes = @(Get-MilestoneEventTypes | ForEach-Object { [PSCustomObject]@{ id = $_.id; name = $_.name } })
$inputs = @(Get-MilestoneInputs | ForEach-Object { [PSCustomObject]@{ id = $_.id; name = $_.name; type = "input" } })
$outputs = @(Get-MilestoneOutputs | ForEach-Object { [PSCustomObject]@{ id = $_.id; name = $_.name; type = "output" } })
$ioList = @($inputs) + @($outputs)

$result = @{
    cameras   = $cameras
    eventTypes = $eventTypes
    ioList    = $ioList
}
$result | ConvertTo-Json -Depth 4 -Compress
exit 0

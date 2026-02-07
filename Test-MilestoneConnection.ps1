# Test connection to Milestone XProtect API Gateway
# Adjust $ApiBaseUrl to your XProtect server address (IP or hostname)

$ErrorActionPreference = "Stop"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$credPath = Join-Path $ScriptDir "Credentials.ps1"

if (Test-Path $credPath) {
    . $credPath
    $ApiBaseUrl = $MilestoneApiBaseUrl
    $Username = $MilestoneUsername
    $Password = $MilestonePassword
} else {
    $ApiBaseUrl = "https://localhost"
    $Username = "API"
    $Password = ""
}

# IDP och API (enligt Milestone-dokumentation)
$IdpTokenUrl = $ApiBaseUrl + "/API/IDP/connect/token"
$ApiRestBase = $ApiBaseUrl + "/api/rest/v1"

# Ignore invalid SSL certificate (development/test only)
if ($ApiBaseUrl -like "https://*") {
    [System.Net.ServicePointManager]::ServerCertificateValidationCallback = { $true }
    [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12
}

Write-Host "Milestone API - test connection" -ForegroundColor Cyan
Write-Host "IDP: $IdpTokenUrl"
Write-Host ""

# 1) Get bearer token
Write-Host "1. Getting token from IDP..." -ForegroundColor Yellow
$body = @{
    grant_type = "password"
    username   = $Username
    password   = $Password
    client_id  = "GrantValidatorClient"
}
try {
    $tokenResponse = Invoke-RestMethod -Uri $IdpTokenUrl -Method Post -ContentType "application/x-www-form-urlencoded" -Body $body
} catch {
    Write-Host "Error getting token:" -ForegroundColor Red
    Write-Host $_.Exception.Message
    if ($_.Exception.Response) {
        $reader = New-Object System.IO.StreamReader($_.Exception.Response.GetResponseStream())
        $reader.BaseStream.Position = 0
        Write-Host $reader.ReadToEnd()
    }
    exit 1
}

$token = $tokenResponse.access_token
Write-Host "   Token received (valid for $($tokenResponse.expires_in) seconds)." -ForegroundColor Green
Write-Host ""

# 2) Call Configuration API (list sites)
Write-Host "2. Calling Configuration API (GET /sites)..." -ForegroundColor Yellow
$headers = @{
    Authorization = "Bearer $token"
}
try {
    $sites = Invoke-RestMethod -Uri ($ApiRestBase + "/sites") -Method Get -Headers $headers
} catch {
    Write-Host "Error calling API:" -ForegroundColor Red
    Write-Host $_.Exception.Message
    if ($_.Exception.Response) {
        $reader = New-Object System.IO.StreamReader($_.Exception.Response.GetResponseStream())
        $reader.BaseStream.Position = 0
        Write-Host $reader.ReadToEnd()
    }
    exit 1
}

$siteList = $sites.array
if (-not $siteList) {
    Write-Host "   No sites returned (possibly empty installation)." -ForegroundColor Yellow
} else {
    Write-Host "   Sites:" -ForegroundColor Green
    foreach ($s in $siteList) {
        Write-Host "   - $($s.displayName) (id: $($s.id))"
    }
}

Write-Host ""
Write-Host "Done. Connection to Milestone API works." -ForegroundColor Green

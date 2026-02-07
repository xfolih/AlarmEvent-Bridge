# Enkel lokal webhook-mottagare for test.
# For att ta emot fran XProtect-datorn pa natverket: anvand -BindAddress med denna datorns IP.
# Avbryt med Ctrl+C.
#
# Lokal test (samma dator):     .\Start-WebhookReceiver.ps1
# Fran annan dator (natverk):   .\Start-WebhookReceiver.ps1 -BindAddress 192.168.0.38
# Anpassad port:                .\Start-WebhookReceiver.ps1 -BindAddress 192.168.0.38 -Port 8765

param(
    [string]$BindAddress = "127.0.0.1",
    [int]$Port = 8765
)

$ErrorActionPreference = "Stop"
# Lyssnar pa roten sa vilken path som helst fungerar (t.ex. /46001/ID001/01/Kamera%20trapp%20-%20motion%20detected)
$url = "http://${BindAddress}:${Port}/"

Write-Host "Webhook-mottagare startar pa $url" -ForegroundColor Cyan
Write-Host "Alla paths accepteras (t.ex. /46001/ID001/01/Kamera%20trapp%20-%20motion%20detected)" -ForegroundColor Gray
if ($BindAddress -ne "127.0.0.1") {
    Write-Host "Ange i Milestone Setup webhook-URL: http://${BindAddress}:${Port}/46001/ID001/01/din-beskrivning" -ForegroundColor Yellow
} else {
    Write-Host "Lokal test-URL: http://127.0.0.1:${Port}/webhook" -ForegroundColor Yellow
}
Write-Host "Avbryt med Ctrl+C." -ForegroundColor Gray
Write-Host ""

$listener = New-Object System.Net.HttpListener
$listener.Prefixes.Add($url)
$listener.Start()

try {
    while ($listener.IsListening) {
        $context = $listener.GetContext()
        $request = $context.Request
        $response = $context.Response
        $response.StatusCode = 200
        $response.ContentType = "application/json"
        $body = "{}"
        $time = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        if ($request.HttpMethod -eq "POST" -and $request.HasEntityBody) {
            $reader = New-Object System.IO.StreamReader($request.InputStream, $request.ContentEncoding)
            $body = $reader.ReadToEnd()
            $reader.Close()
            $request.InputStream.Close()
            Write-Host "[$time] POST $($request.Url.LocalPath)" -ForegroundColor Green
            Write-Host $body
            Write-Host ""
        } else {
            Write-Host "[$time] $($request.HttpMethod) $($request.Url.LocalPath)" -ForegroundColor Gray
        }
        $buf = [System.Text.Encoding]::UTF8.GetBytes($body)
        $response.ContentLength64 = $buf.Length
        $response.OutputStream.Write($buf, 0, $buf.Length)
        $response.OutputStream.Close()
    }
} finally {
    $listener.Stop()
    Write-Host "Avslutat." -ForegroundColor Gray
}

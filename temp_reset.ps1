$ErrorActionPreference = 'Stop'

$headers = @{
    'Authorization' = 'Bearer 123'
    'Content-Type'  = 'application/json'
}

$uri = 'https://diapalet-staging.up.railway.app/api/terminal/dev-reset'

try {
    $response = Invoke-WebRequest -Uri $uri -Method POST -Headers $headers -Body '{}'
    Write-Host "Basarili:"
    Write-Host $response.Content
} catch {
    Write-Host "Hata: $($_.Exception.Message)"
    if ($_.Exception.Response) {
        try {
            $stream = $_.Exception.Response.GetResponseStream()
            $reader = New-Object System.IO.StreamReader($stream)
            $details = $reader.ReadToEnd()
            $reader.Close()
            $stream.Close()
            Write-Host "Detay:"
            Write-Host $details
        } catch {
            Write-Host "Hata: Sunucu yanitinin detaylari okunamadi."
        }
    }
}

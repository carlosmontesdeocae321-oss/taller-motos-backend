<#
PowerShell script to test Render-deployed backend endpoints for Taller de Motos.
Usage: run in PowerShell on your machine. It will prompt for values.
#>

param()

Write-Host "Taller de Motos - Helper de prueba (Windows)" -ForegroundColor Cyan

# Base URL (default localhost)
$default = 'http://localhost:3000'
$baseUrl = Read-Host "Introduce la URL base del servidor (por defecto: $default)"
if (-not $baseUrl) { $baseUrl = $default }
if ($baseUrl.EndsWith('/')) { $baseUrl = $baseUrl.TrimEnd('/') }

Write-Host "Usando base URL: $baseUrl`n"

function Invoke-Json { param($url, $method='GET', $body=$null)
    try {
        if ($body) {
            $json = $body | ConvertTo-Json -Depth 10
            $resp = Invoke-RestMethod -Uri $url -Method $method -ContentType 'application/json' -Body $json -ErrorAction Stop
        } else {
            $resp = Invoke-RestMethod -Uri $url -Method $method -ErrorAction Stop
        }
        return @{ ok=$true; data=$resp }
    } catch {
        return @{ ok=$false; error=$_.Exception.Message; response = $_.ErrorDetails }
    }
}

# 1) /features
Write-Host "1) GET /features" -ForegroundColor Yellow
$r = Invoke-Json "$baseUrl/features"
if ($r.ok) { Write-Host "Respuesta:`n"; $r.data | ConvertTo-Json -Depth 5 | Write-Host } else { Write-Host "Error: $($r.error)" -ForegroundColor Red }

# 2) /cloudinary-sign
Write-Host "`n2) GET /cloudinary-sign" -ForegroundColor Yellow
$sig = Invoke-Json "$baseUrl/cloudinary-sign"
if ($sig.ok) { $sig.data | ConvertTo-Json -Depth 5 | Write-Host } else { Write-Host "Opción firmada no disponible: $($sig.error)" -ForegroundColor DarkYellow }

# 3) /upload (server-side test - multipart)
$doUpload = Read-Host "¿Probar upload al servidor local /upload? (y/N)"
if ($doUpload -and $doUpload.ToLower().StartsWith('y')) {
    $filePath = Read-Host "Ruta local de la imagen a subir (jpg/png)"
    if (-not (Test-Path $filePath)) { Write-Host "Archivo no encontrado: $filePath" -ForegroundColor Red; exit 1 }
    Write-Host "Subiendo $filePath a $baseUrl/upload ..." -ForegroundColor Cyan
    try {
        $form = @{ file = Get-Item $filePath }
        $resp = Invoke-RestMethod -Uri "$baseUrl/upload" -Method Post -Form $form -ErrorAction Stop
        Write-Host "Respuesta de upload:`n"; $resp | ConvertTo-Json -Depth 8 | Write-Host
    } catch {
        Write-Host "Fallo en upload: $($_.Exception.Message)" -ForegroundColor Red
    }
}

# 4) Signed upload (cliente -> Cloudinary)
$doSigned = Read-Host "¿Probar subida firmada a Cloudinary (cliente->Cloudinary)? (y/N)"
if ($doSigned -and $doSigned.ToLower().StartsWith('y')) {
    if (-not $sig.ok) { Write-Host "No se puede obtener firma desde el servidor — omitiendo subida firmada." -ForegroundColor Red }
    else {
        $cloudName = $sig.data.cloud_name
        $apiKey = $sig.data.api_key
        $timestamp = $sig.data.timestamp
        $signature = $sig.data.signature
        Write-Host "Firma obtenida. Subiendo a Cloudinary..." -ForegroundColor Cyan
        $filePath = Read-Host "Ruta local de la imagen a subir (jpg/png)"
        if (-not (Test-Path $filePath)) { Write-Host "Archivo no encontrado: $filePath" -ForegroundColor Red; exit 1 }
        $cloudUrl = "https://api.cloudinary.com/v1_1/$cloudName/image/upload"

        # Intentar con Invoke-RestMethod (PowerShell) para multipart/form-data
        try {
            $form = @{
                file = Get-Item $filePath
                api_key = $apiKey
                timestamp = $timestamp
                signature = $signature
                folder = 'taller-motos/uploads'
            }
            $cloudResp = Invoke-RestMethod -Uri $cloudUrl -Method Post -Form $form -ErrorAction Stop
            Write-Host "Respuesta Cloudinary:`n"; $cloudResp | ConvertTo-Json -Depth 8 | Write-Host
        } catch {
            Write-Host "Invoke-RestMethod falló para Cloudinary: $($_.Exception.Message)" -ForegroundColor Yellow
            Write-Host "Intentando con curl si está disponible..." -ForegroundColor Cyan
            try {
                & curl -s -X POST $cloudUrl -F ("file=@$filePath") -F ("api_key=$apiKey") -F ("timestamp=$timestamp") -F ("signature=$signature") -F ("folder=taller-motos/uploads") -o cloud_resp.json
                if (Test-Path cloud_resp.json) { Write-Host "Respuesta Cloudinary (curl):"; Get-Content cloud_resp.json | Out-String | Write-Host }
            } catch {
                Write-Host "Curl no disponible o falló: $($_.Exception.Message)" -ForegroundColor Red
            }
        }
    }
}

# 5) Crear cliente, moto y servicio
$doCreate = Read-Host "¿Crear cliente + moto + servicio de prueba? (y/N)"
if ($doCreate -and $doCreate.ToLower().StartsWith('y')) {
    Write-Host "Creando cliente..." -ForegroundColor Cyan
    $clientResp = Invoke-Json "$baseUrl/clients" 'POST' @{ nombre='Cliente Prueba'; telefono='555-0000'; direccion='Calle Prueba' }
    if (-not $clientResp.ok) { Write-Host "Fallo al crear cliente: $($clientResp.error)" -ForegroundColor Red; exit 1 }
    $clientId = $clientResp.data.id_cliente
    Write-Host "Cliente creado: id_cliente=$clientId"

    Write-Host "Creando moto..." -ForegroundColor Cyan
    $motoResp = Invoke-Json "$baseUrl/motos" 'POST' @{ id_cliente = $clientId; marca='Marca'; modelo='Modelo'; anio=2023 }
    if (-not $motoResp.ok) { Write-Host "Fallo al crear moto: $($motoResp.error)" -ForegroundColor Red; exit 1 }
    $motoId = $motoResp.data.id_moto
    Write-Host "Moto creada: id_moto=$motoId"

    $useCloudUrl = Read-Host "Si subiste a Cloudinary pega aquí la 'secure_url' (Enter para usar upload multipart en backend)"
    if ($useCloudUrl) {
        Write-Host "Creando servicio referenciando URL de Cloudinary..." -ForegroundColor Cyan
        $serviceResp = Invoke-Json "$baseUrl/services" 'POST' @{ id_moto = $motoId; descripcion='Servicio prueba (cloud)'; fecha=(Get-Date).ToString('yyyy-MM-dd'); costo = 10.5; image_path=$useCloudUrl }
        if ($serviceResp.ok) { Write-Host "Servicio creado:`n"; $serviceResp.data | ConvertTo-Json -Depth 5 | Write-Host } else { Write-Host "Fallo al crear servicio: $($serviceResp.error)" -ForegroundColor Red }
    } else {
        Write-Host "Creando servicio usando multipart (servidor hará upload)..." -ForegroundColor Cyan
        $filePath = Read-Host "Ruta local de la imagen para el servicio (o Enter para sin imagen)"
        if ($filePath -and (Test-Path $filePath)) {
            try {
                $form = @{
                    id_moto = $motoId
                    descripcion = 'Servicio prueba (multipart)'
                    fecha = (Get-Date).ToString('yyyy-MM-dd')
                    costo = '15.0'
                    image = Get-Item $filePath
                }
                $resp = Invoke-RestMethod -Uri "$baseUrl/services" -Method Post -Form $form -ErrorAction Stop
                Write-Host "Servicio creado (multipart):`n"; $resp | ConvertTo-Json -Depth 8 | Write-Host
            } catch {
                Write-Host "Fallo al crear servicio multipart: $($_.Exception.Message)" -ForegroundColor Red
            }
        } else {
            $serviceResp = Invoke-Json "$baseUrl/services" 'POST' @{ id_moto = $motoId; descripcion='Servicio prueba (sin imagen)'; fecha=(Get-Date).ToString('yyyy-MM-dd'); costo = 5.0 }
            if ($serviceResp.ok) { Write-Host "Servicio creado:`n"; $serviceResp.data | ConvertTo-Json -Depth 5 | Write-Host } else { Write-Host "Fallo al crear servicio: $($serviceResp.error)" -ForegroundColor Red }
        }
    }

    # 6) Generar factura
    $doInvoice = Read-Host "¿Generar PDF de factura para la moto id $motoId ahora? (y/N)"
    if ($doInvoice -and $doInvoice.ToLower().StartsWith('y')) {
        Write-Host "Solicitando factura..." -ForegroundColor Cyan
        $out = Join-Path -Path $PWD -ChildPath ("invoice_moto_${motoId}.pdf")
        try {
            $body = @{ id_moto = $motoId } | ConvertTo-Json
            Invoke-WebRequest -Uri "$baseUrl/invoices" -Method Post -ContentType 'application/json' -Body $body -OutFile $out -ErrorAction Stop
            if (Test-Path $out) { Write-Host "Factura guardada en: $out"; Start-Process $out } else { Write-Host "No se guardó la factura." -ForegroundColor Red }
        } catch {
            Write-Host "Fallo al solicitar factura: $($_.Exception.Message)" -ForegroundColor Red
        }
    }
}

Write-Host "`nTerminado. Si algo falló, revisa que el servidor esté corriendo en $baseUrl y consulta los logs." -ForegroundColor Green

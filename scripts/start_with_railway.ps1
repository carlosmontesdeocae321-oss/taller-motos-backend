<#
Script interactivo para arrancar el servidor local apuntando a una base de datos Railway.
No escribe credenciales en el repo; pide la URL y arranca `node index.js` con las vars en memoria.

Usage: desde PowerShell en `c:\backend` ejecutar:
  .\scripts\start_with_railway.ps1

Ejemplo de URL esperada:
  mysql://root:password@host:3306/dbname
#>

Write-Host "Start server with Railway DB - helper" -ForegroundColor Cyan

$uri = Read-Host "Pega la URL de conexión MySQL (mysql://user:pass@host:port/dbname)"
if (-not $uri) { Write-Host "No se proporcionó URL. Abortando." -ForegroundColor Red; exit 1 }

$pattern = 'mysql:\/\/(?<user>[^:\/]+):(?<pass>[^@]+)@(?<host>[^:\/]+):(?<port>\d+)\/(?<db>[^\s\?]+)'
$m = [regex]::Match($uri, $pattern)
if (-not $m.Success) { Write-Host "URL inválida. Asegúrate del formato mysql://user:pass@host:port/dbname" -ForegroundColor Red; exit 1 }

$user = $m.Groups['user'].Value
$pass = $m.Groups['pass'].Value
$host = $m.Groups['host'].Value
$port = $m.Groups['port'].Value
$db = $m.Groups['db'].Value

Write-Host "Conectando a DB: $db @ $host:$port como $user" -ForegroundColor Yellow

# Set environment variables for this PowerShell session
$env:DB_HOST = $host
$env:DB_PORT = $port
$env:DB_USER = $user
$env:DB_PASSWORD = $pass
$env:DB_NAME = $db

Write-Host "Variables de entorno establecidas (sólo para esta sesión). Arrancando servidor..." -ForegroundColor Green

try {
    # Ejecutar node en la misma sesión para heredar variables
    node index.js
} catch {
    Write-Host "Error arrancando node: $($_.Exception.Message)" -ForegroundColor Red
}

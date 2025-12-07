# Start backend with Railway-provided MySQL credentials (powershell helper)
# Usage: .\start_with_railway.ps1

$env:DB_HOST = "mainline.proxy.rlwy.net"
$env:DB_PORT = "30789"
$env:DB_USER = "root"
$env:DB_PASSWORD = "WtVyJLqBtUWzKCdfJKpwSacuuegsErPJ"
$env:DB_NAME = "railway"
$env:PORT = "3000"

Write-Host "Starting backend with Railway DB host $env:DB_HOST:$env:DB_PORT (DB_NAME=$env:DB_NAME)"

npm ci
node index.js

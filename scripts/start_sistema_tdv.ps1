# Arranca el Sistema TDV (servidor web waitress + workers) en el servidor.
# Uso: powershell -ExecutionPolicy Bypass -File .\scripts\start_sistema_tdv.ps1
#
# - El servidor web es waitress (no runserver).
# - La salida de cada proceso queda en runtime\logs\<nombre>.log
# - Se puede correr varias veces: no duplica procesos que ya estan arriba.

$ErrorActionPreference = "Stop"

$Root = Split-Path -Parent $PSScriptRoot
Set-Location -LiteralPath $Root

$Python = Join-Path $Root ".venv\Scripts\python.exe"
if (-not (Test-Path -LiteralPath $Python)) {
    throw "No se encontro el venv: $Python"
}

# Cargar variables del .env al entorno (las heredan todos los procesos)
$EnvFile = Join-Path $Root ".env"
if (Test-Path -LiteralPath $EnvFile) {
    Get-Content -LiteralPath $EnvFile | ForEach-Object {
        $line = $_.Trim()
        if (-not $line -or $line.StartsWith("#")) { return }
        $parts = $line -split "=", 2
        if ($parts.Count -lt 2) { return }
        $name = $parts[0].Trim()
        $value = $parts[1].Trim().Trim('"').Trim("'")
        Set-Item -Path "Env:$name" -Value $value
    }
}

# Que Python escriba en el log al momento (sin buffer)
$env:PYTHONUNBUFFERED = "1"

$Runtime = Join-Path $Root "runtime"
$Logs = Join-Path $Runtime "logs"
New-Item -ItemType Directory -Force -Path $Logs | Out-Null

# Procesos del sistema que ya estan corriendo
function Get-TdvProcesos {
    Get-CimInstance Win32_Process -Filter "Name='python.exe'" -ErrorAction SilentlyContinue |
        Where-Object {
            $_.CommandLine -and (
                $_.CommandLine -like "*waitress*config.wsgi*" -or
                $_.CommandLine -like "*manage.py*procesar_generaciones_*"
            )
        }
}

# Borrar candados viejos solo si no hay workers vivos
# (si hay workers corriendo, sus candados son validos).
$workersVivos = Get-TdvProcesos | Where-Object { $_.CommandLine -like "*procesar_generaciones_*" }
if (-not $workersVivos) {
    Get-ChildItem -LiteralPath $Runtime -Filter "*_worker.lock" -ErrorAction SilentlyContinue |
        Remove-Item -Force -ErrorAction SilentlyContinue
}

# Si un log pasa de 20 MB, se guarda como .old.log y se empieza uno nuevo
function Limitar-Log {
    param([string]$Ruta)
    if ((Test-Path -LiteralPath $Ruta) -and ((Get-Item -LiteralPath $Ruta).Length -gt 20MB)) {
        $viejo = [System.IO.Path]::ChangeExtension($Ruta, ".old.log")
        Move-Item -LiteralPath $Ruta -Destination $viejo -Force
    }
}

# Lanza python oculto, con stdout y stderr al log del proceso
function Start-TdvProcess {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][string]$PyArgs
    )
    $log = Join-Path $Logs "$Name.log"
    Limitar-Log -Ruta $log
    Add-Content -LiteralPath $log -Value "===== Inicio $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') ====="
    Start-Process -FilePath "cmd.exe" `
        -WorkingDirectory $Root `
        -WindowStyle Hidden `
        -ArgumentList "/c `"`"$Python`" $PyArgs >> `"$log`" 2>&1`"" | Out-Null
    Write-Host "Iniciado: $Name"
}

# ---- Servidor web (waitress) ----
$web = Get-TdvProcesos | Where-Object { $_.CommandLine -like "*waitress*config.wsgi*" }
if ($web) {
    Write-Host "El servidor web ya estaba en ejecucion (PID $($web.ProcessId -join ', '))"
} else {
    Start-TdvProcess -Name "web" -PyArgs "-m waitress --listen=0.0.0.0:8000 --threads=8 config.wsgi:application"
}

# ---- Workers (uno por cliente) ----
$Workers = @(
    "procesar_generaciones_dimanno",
    "procesar_generaciones_master",
    "procesar_generaciones_orsero",
    "procesar_generaciones_kraaijeveld",
    "procesar_generaciones_sifa",
    "procesar_generaciones_glamour",
    "procesar_generaciones_nufri",
    "procesar_generaciones_eurobanan",
    "procesar_generaciones_tdv_europa",
    "procesar_generaciones_fruver",
    "procesar_generaciones_visafruits"
)

foreach ($cmd in $Workers) {
    $existe = Get-TdvProcesos | Where-Object { $_.CommandLine -like "*manage.py*$cmd*" }
    if ($existe) {
        Write-Host "Ya corria: $cmd"
        continue
    }
    Start-TdvProcess -Name $cmd -PyArgs "manage.py $cmd"
}

Write-Host ""
Write-Host "Sistema TDV en marcha."
Write-Host "Logs en:         $Logs"
Write-Host "Login local:     http://127.0.0.1:8000/"
$nombrePc = $env:COMPUTERNAME
if ($nombrePc) {
    Write-Host "Login por nombre: http://${nombrePc}:8000/"
}
$ipLan = @(
    Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
        Where-Object { $_.IPAddress -notlike "127.*" -and $_.IPAddress -notlike "169.254.*" } |
        Select-Object -ExpandProperty IPAddress -First 1
)
if ($ipLan) {
    Write-Host "Login por IP:    http://${ipLan}:8000/"
}
Write-Host "Para detener: scripts\stop_sistema_tdv.ps1"